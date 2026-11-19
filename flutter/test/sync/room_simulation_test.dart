import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/clock_sync.dart';
import 'package:reelay/sync/guest_playback_reconciler.dart';
import 'package:reelay/sync/host_playback_coordinator.dart';
import 'package:reelay/sync/synced_player.dart';

/// A player that actually plays: position advances in real (fake) time
/// while playing and not buffering, and each seek can cost [seekLatencyMs]
/// of buffering — what a remote Plex transcode does when it has to
/// produce segments at the new spot.
class _SimPlayer implements SyncedPlayer {
  _SimPlayer({required this.seekLatencyMs, int startMs = 0}) : _position = startMs {
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isPlaying && _state == SyncPlaybackState.ready) _position += 50;
    });
  }

  final int seekLatencyMs;
  late final Timer _ticker;
  Timer? _rebuffer;
  final List<SyncedPlayerListener> _listeners = [];
  bool _isPlaying = false;
  int _position;
  SyncPlaybackState _state = SyncPlaybackState.ready;
  final List<int> seeks = [];

  @override
  int get duration => 3 * 3600 * 1000;
  @override
  bool get isPlaying => _isPlaying;
  @override
  int get currentPosition => _position;
  @override
  SyncPlaybackState get playbackState => _state;

  void _setState(SyncPlaybackState s) {
    if (_state == s) return;
    _state = s;
    for (final l in List.of(_listeners)) {
      l.onPlaybackStateChanged?.call(s);
    }
  }

  @override
  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(true, true);
    }
  }

  @override
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(false, true);
    }
  }

  @override
  void seekTo(int positionMs) {
    seeks.add(positionMs);
    _position = positionMs;
    for (final l in List.of(_listeners)) {
      l.onSeek?.call(positionMs);
    }
    if (seekLatencyMs > 0) {
      _setState(SyncPlaybackState.buffering);
      _rebuffer?.cancel();
      _rebuffer = Timer(Duration(milliseconds: seekLatencyMs), () => _setState(SyncPlaybackState.ready));
    }
  }

  @override
  void addListener(SyncedPlayerListener listener) => _listeners.add(listener);
  @override
  void removeListener(SyncedPlayerListener listener) => _listeners.remove(listener);

  void dispose() {
    _ticker.cancel();
    _rebuffer?.cancel();
  }
}

class _Room {
  _Room({required int guestSeekLatencyMs, int hostStartMs = 0, int guestStartMs = 0})
    : host = _SimPlayer(seekLatencyMs: 0, startMs: hostStartMs),
      guest = _SimPlayer(seekLatencyMs: guestSeekLatencyMs, startMs: guestStartMs);

  static const _relayMs = 80;

  final _SimPlayer host;
  final _SimPlayer guest;
  late final HostPlaybackCoordinator coordinator;
  late final GuestPlaybackReconciler reconciler;

  void _later(void Function() f) => Timer(const Duration(milliseconds: _relayMs), f);

  void start() {
    coordinator = HostPlaybackCoordinator(
      myPeerId: 'host',
      player: host,
      sendState: (s) => _later(() => reconciler.onState(s)),
    );
    reconciler = GuestPlaybackReconciler(
      myPeerId: 'guest',
      player: guest,
      clock: ClockSync(sendPing: (_) {}),
      sendControl: (r) => _later(() => coordinator.onControlRequest('guest', r)),
      sendStatus: (s) => _later(() => coordinator.onPeerStatus('guest', s)),
    );
    coordinator.onPeerJoined('guest');
    coordinator.start();
    reconciler.start();
    host.play(); // the player screen calls play() once it's attached
  }

  void stop() {
    coordinator.stop();
    reconciler.stop();
    host.dispose();
    guest.dispose();
  }

  int get drift => (host.currentPosition - guest.currentPosition).abs();
}

void main() {
  for (final latency in [500, 1200, 2000, 2400, 3000, 4000, 6000, 10000]) {
    test('host rewinds; a guest whose seeks take ${latency}ms settles back in sync', () {
      fakeAsync((async) {
        final room = _Room(guestSeekLatencyMs: latency, hostStartMs: 600000, guestStartMs: 600000)..start();
        async.elapse(const Duration(seconds: 10));
        expect(room.host.isPlaying, isTrue);
        expect(room.drift, lessThan(1500));

        final seeksBefore = room.guest.seeks.length;
        room.host.seekTo(room.host.currentPosition - 30000); // the host presses rewind
        async.elapse(const Duration(seconds: 60));

        final guestSeeks = room.guest.seeks.length - seeksBefore;
        // ignore: avoid_print
        print('latency ${latency}ms: guest seeks after rewind = $guestSeeks, '
            'drift = ${room.drift}ms, host playing = ${room.host.isPlaying}, guest playing = ${room.guest.isPlaying}');
        expect(room.drift, lessThan(1500));
        expect(guestSeeks, lessThanOrEqualTo(2));
        room.stop();
      });
    });

    test('the guest rewinds; a guest whose seeks take ${latency}ms settles back in sync', () {
      fakeAsync((async) {
        final room = _Room(guestSeekLatencyMs: latency, hostStartMs: 600000, guestStartMs: 600000)..start();
        async.elapse(const Duration(seconds: 10));
        final seeksBefore = room.guest.seeks.length;
        room.guest.seekTo(room.guest.currentPosition - 30000); // the guest presses rewind
        async.elapse(const Duration(seconds: 60));
        // ignore: avoid_print
        print('guest rewind, latency ${latency}ms: guest seeks = ${room.guest.seeks.length - seeksBefore}, drift = ${room.drift}ms');
        expect(room.drift, lessThan(1500));
        expect(room.host.isPlaying, isTrue);
        expect(room.guest.seeks.length - seeksBefore, lessThanOrEqualTo(4)); // its own seek, then catching up
        room.stop();
      });
    });

    test('a fresh room where each side resumes somewhere different settles (${latency}ms seeks)', () {
      fakeAsync((async) {
        final room = _Room(guestSeekLatencyMs: latency, hostStartMs: 600000, guestStartMs: 590000)..start();
        async.elapse(const Duration(seconds: 60));
        // ignore: avoid_print
        print('fresh room, latency ${latency}ms: guest seeks = ${room.guest.seeks.length}, drift = ${room.drift}ms');
        expect(room.drift, lessThan(1500));
        expect(room.guest.seeks.length, lessThanOrEqualTo(2));
        room.stop();
      });
    });
  }
}
