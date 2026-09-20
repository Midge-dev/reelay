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
}
