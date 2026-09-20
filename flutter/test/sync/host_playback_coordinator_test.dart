import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/host_playback_coordinator.dart';
import 'package:reelay/sync/playback_state.dart';

import 'fake_synced_player.dart';

void main() {
  test('a solo host (no peers) auto-starts playback as soon as it is ready', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final coordinator = HostPlaybackCoordinator(
        myPeerId: 'host',
        player: player,
        sendState: broadcasts.add,
      );

      coordinator.start();
      expect(broadcasts, isEmpty, reason: 'nothing to report until the player has loaded');

      player.becomeReady();
      async.elapse(const Duration(seconds: 1));

      expect(player.isPlaying, isTrue);
      expect(broadcasts.last.phase, PlaybackPhase.playing);

      coordinator.stop();
    });
  });

  test('a host with one not-yet-ready peer waits before starting', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final coordinator = HostPlaybackCoordinator(
        myPeerId: 'host',
        player: player,
        sendState: broadcasts.add,
      );

      coordinator.start();
      coordinator.onPeerJoined('guest-1');
      player.becomeReady();
      async.elapse(const Duration(seconds: 1));

      expect(player.isPlaying, isFalse, reason: 'still gated on guest-1 never reporting ready');
      expect(broadcasts.last.phase, PlaybackPhase.waitingForPeers);
      expect(broadcasts.last.waitingOn, contains('guest-1'));

      coordinator.stop();
    });
  });

  test('the gating peer becoming ready releases playback', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final coordinator = HostPlaybackCoordinator(
        myPeerId: 'host',
        player: player,
        sendState: broadcasts.add,
      );

      coordinator.start();
      coordinator.onPeerJoined('guest-1');
      player.becomeReady();
      async.elapse(const Duration(seconds: 1));
      expect(player.isPlaying, isFalse);

      coordinator.onPeerStatus('guest-1', const PeerStatus(ready: true, buffering: false, positionMs: 0));
      async.elapse(const Duration(seconds: 1));

      expect(player.isPlaying, isTrue);
      expect(broadcasts.last.phase, PlaybackPhase.playing);

      coordinator.stop();
    });
  });

  test('a peer that stays buffering past the stall grace period re-gates a playing room', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final coordinator = HostPlaybackCoordinator(
        myPeerId: 'host',
        player: player,
        sendState: broadcasts.add,
      );

      coordinator.start();
      player.becomeReady();
      async.elapse(const Duration(seconds: 1));
      expect(player.isPlaying, isTrue, reason: 'solo host should already be playing');

      coordinator.onPeerJoined('guest-1');
      coordinator.onPeerStatus('guest-1', const PeerStatus(ready: true, buffering: true, positionMs: 0));

      // Under the 2.5s stall grace period: not gated yet.
      async.elapse(const Duration(milliseconds: 2000));
      expect(broadcasts.last.phase, PlaybackPhase.playing);

      // Past the grace period, still buffering: now gates playback.
      async.elapse(const Duration(milliseconds: 1000));
      expect(player.isPlaying, isFalse);
      expect(broadcasts.last.phase, PlaybackPhase.waitingForPeers);

      coordinator.stop();
    });
  });
}
