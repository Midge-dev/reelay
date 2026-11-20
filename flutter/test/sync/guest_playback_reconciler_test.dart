import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/clock_sync.dart';
import 'package:reelay/sync/guest_playback_reconciler.dart';
import 'package:reelay/sync/playback_state.dart';

import 'fake_synced_player.dart';

void main() {
  test('a guest starts playing once told PLAYING and within the deadband', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final clock = ClockSync(sendPing: (_) {});
      final sentControl = <ControlRequest>[];
      final sentStatus = <PeerStatus>[];
      final reconciler = GuestPlaybackReconciler(
        myPeerId: 'guest',
        player: player,
        clock: clock,
        sendControl: sentControl.add,
        sendStatus: sentStatus.add,
      );

      reconciler.start();
      player.becomeReady();

      reconciler.onState(PlaybackState(
        seq: 1,
        phase: PlaybackPhase.playing,
        anchorPositionMs: 0,
        anchorHostTimeMs: clock.hostNowMs(), // already started, no future scheduling
      ));
      async.elapse(const Duration(milliseconds: 600)); // past one 500ms tick

      expect(player.isPlaying, isTrue);

      reconciler.stop();
    });
  });

  test('drift beyond the deadband triggers a hard seek toward the target', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final clock = ClockSync(sendPing: (_) {});
      final reconciler = GuestPlaybackReconciler(
        myPeerId: 'guest',
        player: player,
        clock: clock,
        sendControl: (_) {},
        sendStatus: (_) {},
      );

      reconciler.start();
      player.becomeReady();

      final anchorHostTime = clock.hostNowMs();
      reconciler.onState(PlaybackState(
        seq: 1,
        phase: PlaybackPhase.playing,
        anchorPositionMs: 10000, // host is already 10s in
        anchorHostTimeMs: anchorHostTime,
      ));
      async.elapse(const Duration(milliseconds: 600));

      // Local player never actually moved (starts at 0), so it's ~10s
      // behind the target — well past the 1.5s deadband.
      expect(player.currentPosition, greaterThan(8000));

      reconciler.stop();
    });
  });

  test('a scheduled future start does not play early', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final clock = ClockSync(sendPing: (_) {});
      final reconciler = GuestPlaybackReconciler(
        myPeerId: 'guest',
        player: player,
        clock: clock,
        sendControl: (_) {},
        sendStatus: (_) {},
      );

      reconciler.start();
      player.becomeReady();

      final futureStart = clock.hostNowMs() + 2000; // host wants playback to begin in 2s
      reconciler.onState(PlaybackState(
        seq: 1,
        phase: PlaybackPhase.playing,
        anchorPositionMs: 0,
        anchorHostTimeMs: futureStart,
      ));
      async.elapse(const Duration(milliseconds: 600));
      expect(player.isPlaying, isFalse, reason: 'the scheduled start time has not arrived yet');

      async.elapse(const Duration(milliseconds: 1600)); // now past the 2s mark
      expect(player.isPlaying, isTrue);

      reconciler.stop();
    });
  });

  // Inside the 1.5s seek deadband a guest closes the gap by playing a
  // little fast or slow — no seek, so no rebuffer.
  group('drift inside the deadband: speed, not a seek', () {
    late FakeSyncedPlayer player;
    late ClockSync clock;
    late GuestPlaybackReconciler reconciler;
    var seq = 0;

    /// The host says: playing, at [positionMs] now.
    void playingAt(int positionMs, {PlaybackPhase phase = PlaybackPhase.playing}) => reconciler.onState(PlaybackState(
          seq: ++seq,
          phase: phase,
          anchorPositionMs: positionMs,
          anchorHostTimeMs: clock.hostNowMs(),
        ));

    void startAt(int offMs, FakeAsync async) {
      player = FakeSyncedPlayer();
      clock = ClockSync(sendPing: (_) {});
      reconciler = GuestPlaybackReconciler(myPeerId: 'guest', player: player, clock: clock, sendControl: (_) {}, sendStatus: (_) {});
      reconciler.start();
      player.becomeReady();
      player.advancePosition(60000 + offMs);
      playingAt(60000);
    }

    test('most of a second behind: 10% fast, and no seek', () {
      fakeAsync((async) {
        startAt(-800, async);
        expect(player.rate, 1.10);
        expect(player.currentPosition, 59200, reason: 'no seek');
        reconciler.stop();
      });
    });

    test('a little ahead: 5% slow', () {
      fakeAsync((async) {
        startAt(300, async);
        expect(player.rate, 0.95);
        reconciler.stop();
      });
    });

    test('within what the clocks can tell apart: real time', () {
      fakeAsync((async) {
        startAt(-100, async);
        expect(player.rate, 1.0);
        reconciler.stop();
      });
    });

    test('once nudging, it keeps on until nearly there, then back to real time', () {
      fakeAsync((async) {
        startAt(-300, async);
        expect(player.rate, 1.05);
        player.advancePosition(200); // 100 behind: still closing
        playingAt(60000);
        expect(player.rate, 1.05);
        player.advancePosition(70); // 30 behind
        playingAt(60000);
        expect(player.rate, 1.0);
        reconciler.stop();
      });
    });

    test('real time again while buffering, paused, or once the room stops', () {
      fakeAsync((async) {
        startAt(-800, async);
        player.setBuffering(true);
        playingAt(60000);
        expect(player.rate, 1.0, reason: 'buffering');
        player.setBuffering(false);
        playingAt(60000);
        expect(player.rate, 1.10);
        reconciler.stop();
        expect(player.rate, 1.0, reason: 'stopped');
      });
    });

    test('a paused room is real time — and lined up by a seek, as before', () {
      fakeAsync((async) {
        startAt(-800, async);
        playingAt(60000, phase: PlaybackPhase.paused);
        expect(player.rate, 1.0);
        expect(player.currentPosition, 60000);
        reconciler.stop();
        expect(player.rate, 1.0, reason: 'stopped');
      });
    });

    test('past the deadband it seeks, at real time', () {
      fakeAsync((async) {
        startAt(-3000, async);
        expect(player.rate, 1.0);
        expect(player.currentPosition, greaterThanOrEqualTo(60000), reason: 'a seek to the host');
        reconciler.stop();
      });
    });
  });
}
