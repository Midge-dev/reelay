import 'dart:async';
import 'dart:math';

import 'package:reelay/sync/synced_player.dart';

/// How one device's player behaves — the things that differ between a
/// Shield direct-playing off a LAN server and one pulling a remote Plex
/// transcode.
class PlayerProfile {
  /// How long a seek takes to play again: picked between these each time.
  final int seekLatencyMinMs;
  final int seekLatencyMaxMs;

  /// `video_player` reports position by polling the platform every 500ms
  /// while playing (and not at all while paused); a seek's new position
  /// shows once the platform call returns, [seekReportMs] later.
  final int positionPollMs;
  final int seekReportMs;

  const PlayerProfile({
    this.seekLatencyMinMs = 0,
    this.seekLatencyMaxMs = 0,
    this.positionPollMs = 500,
    this.seekReportMs = 40,
  });

  /// A LAN direct play: seeks come back almost at once.
  static const directPlay = PlayerProfile(seekLatencyMinMs: 150, seekLatencyMaxMs: 400);

  /// A remote Plex transcode: every seek makes the server encode new
  /// segments before anything plays.
  static const remoteTranscode = PlayerProfile(seekLatencyMinMs: 2000, seekLatencyMaxMs: 3500);

  /// Instant and exact: the old FakeSyncedPlayer's world.
  static const ideal = PlayerProfile(positionPollMs: 0, seekReportMs: 0);

  PlayerProfile copyWith({int? seekLatencyMinMs, int? seekLatencyMaxMs}) => PlayerProfile(
    seekLatencyMinMs: seekLatencyMinMs ?? this.seekLatencyMinMs,
    seekLatencyMaxMs: seekLatencyMaxMs ?? this.seekLatencyMaxMs,
    positionPollMs: positionPollMs,
    seekReportMs: seekReportMs,
  );

  @override
  String toString() => 'seeks $seekLatencyMinMs-${seekLatencyMaxMs}ms, poll ${positionPollMs}ms';
}

/// A [SyncedPlayer] that plays in (fake) time the way `video_player` on
/// ExoPlayer does, as far as the sync engine can tell:
///
/// - `isPlaying` is the intent: it stays true through buffering.
/// - A seek fires `onSeek` synchronously (like VideoPlayerSyncedPlayer),
///   then buffers for the profile's seek latency.
/// - [currentPosition] is what `video_player` would report — polled, so up
///   to [PlayerProfile.positionPollMs] stale — while [truePosition] is the
///   frame actually on screen, which is what the room checks compare.
class SimPlayer implements SyncedPlayer {
  /// [openMs]: how long the stream takes to open — idle (not ready) until
  /// then, as a real player is while it loads.
  SimPlayer(this.profile, {required this.random, int startMs = 0, this.durationMs = 2 * 3600 * 1000, int openMs = 0})
    : _truePos = startMs,
      _reportedPos = startMs {
    _ticker = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
    if (openMs > 0) {
      _opening = true;
      _state = SyncPlaybackState.idle;
      _openTimer = Timer(Duration(milliseconds: openMs), () {
        _opening = false;
        _updateState();
      });
    }
  }

  bool _opening = false;
  Timer? _openTimer;

  static const _tickMs = 50;

  final PlayerProfile profile;
  final Random random;
  final int durationMs;
  late final Timer _ticker;
  Timer? _rebuffer;
  Timer? _report;
  Timer? _stallTimer;
  int _sincePollMs = 0;
  final List<SyncedPlayerListener> _listeners = [];

  bool _isPlaying = false;
  int _truePos;
  int _reportedPos;
  bool _seekBuffering = false;
  bool _stalled = false;
  SyncPlaybackState _state = SyncPlaybackState.ready;
  bool _disposed = false;

  int get truePosition => _truePos;

  @override
  int get duration => durationMs;
  @override
  bool get isPlaying => _isPlaying;
  @override
  int get currentPosition => _reportedPos;
  @override
  SyncPlaybackState get playbackState => _state;

  void _tick() {
    if (_isPlaying && _state == SyncPlaybackState.ready) {
      _truePos = min(_truePos + _tickMs, durationMs);
      if (profile.positionPollMs <= 0) {
        _reportedPos = _truePos;
      } else {
        _sincePollMs += _tickMs;
        if (_sincePollMs >= profile.positionPollMs) {
          _sincePollMs = 0;
          _reportedPos = _truePos;
        }
      }
    }
  }

  void _updateState() {
    if (_opening) return;
    final next = (_seekBuffering || _stalled) ? SyncPlaybackState.buffering : SyncPlaybackState.ready;
    if (next == _state) return;
    _state = next;
    for (final l in List.of(_listeners)) {
      l.onPlaybackStateChanged?.call(next);
    }
  }

  @override
  void play() {
    if (_isPlaying || _disposed) return;
    _isPlaying = true;
    _sincePollMs = 0;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(true, true);
    }
  }

  @override
  void pause() {
    if (!_isPlaying || _disposed) return;
    _isPlaying = false;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(false, true);
    }
  }

  @override
  void seekTo(int positionMs) {
    if (_disposed) return;
    final target = positionMs.clamp(0, durationMs);
    _truePos = target;
    for (final l in List.of(_listeners)) {
      l.onSeek?.call(positionMs);
    }
    _report?.cancel();
    if (profile.seekReportMs <= 0) {
      _reportedPos = target;
    } else {
      _report = Timer(Duration(milliseconds: profile.seekReportMs), () => _reportedPos = target);
    }
    final latency = profile.seekLatencyMinMs +
        (profile.seekLatencyMaxMs > profile.seekLatencyMinMs
            ? random.nextInt(profile.seekLatencyMaxMs - profile.seekLatencyMinMs + 1)
            : 0);
    _rebuffer?.cancel();
    if (latency <= 0) {
      _seekBuffering = false; // lands at once, even over an earlier seek still buffering
      _updateState();
      return;
    }
    _seekBuffering = true;
    _updateState();
    _rebuffer = Timer(Duration(milliseconds: latency), () {
      _seekBuffering = false;
      _updateState();
    });
  }

  /// The network hiccups: buffer for [ms] without moving.
  void stall(int ms) {
    _stallTimer?.cancel();
    _stalled = true;
    _updateState();
    _stallTimer = Timer(Duration(milliseconds: ms), () {
      _stalled = false;
      _updateState();
    });
  }

  @override
  void addListener(SyncedPlayerListener listener) => _listeners.add(listener);
  @override
  void removeListener(SyncedPlayerListener listener) => _listeners.remove(listener);

  void dispose() {
    _disposed = true;
    _ticker.cancel();
    _rebuffer?.cancel();
    _report?.cancel();
    _stallTimer?.cancel();
    _openTimer?.cancel();
  }
}
