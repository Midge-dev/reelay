import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/host_playback_coordinator.dart';
import 'package:reelay/sync/playback_state.dart';
import 'package:reelay/sync/synced_player.dart';
import 'package:reelay/sync/time_utils.dart';

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

  test("the host's own play press waits for the room's start time, at the start spot — no seek back, no rebuffer", () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final seeks = <int>[];
      player.addListener(SyncedPlayerListener(onSeek: seeks.add));
      final coordinator = HostPlaybackCoordinator(myPeerId: 'host', player: player, sendState: broadcasts.add);
      coordinator.start();
      coordinator.onPeerJoined('guest');
      coordinator.onPeerStatus('guest', const PeerStatus(ready: true, buffering: false, positionMs: 0));
      player.becomeReady();
      async.elapse(const Duration(seconds: 2)); // the room starts
      player.pressPause();
      async.elapse(const Duration(seconds: 1));
      seeks.clear();

      player.pressPlay(); // the player starts at once, as ExoPlayer does
      async.elapse(const Duration(milliseconds: 1));
      expect(broadcasts.last.phase, PlaybackPhase.playing);
      expect(broadcasts.last.anchorHostTimeMs, greaterThan(nowMs()), reason: 'the room starts a moment from now');
      expect(player.isPlaying, isFalse, reason: 'held at the start spot until then, not running ahead of the room');

      async.elapse(const Duration(seconds: 1));
      expect(player.isPlaying, isTrue, reason: 'playing from the start time');
      expect(seeks, isEmpty, reason: 'nothing to seek back from');
      coordinator.stop();
    });
  });

  test('a seek while the room waits for a stalled guest is where the room resumes — a straggler still on its way to the old spot does not pull the host back (fuzz seed 1975)', () {
    fakeAsync((async) {
      final player = FakeSyncedPlayer();
      final broadcasts = <PlaybackState>[];
      final hostSeeks = <int>[];
      player.addListener(SyncedPlayerListener(onSeek: hostSeeks.add));
      final coordinator = HostPlaybackCoordinator(myPeerId: 'host', player: player, sendState: broadcasts.add);
      coordinator.start();
      for (final g in ['g1', 'g2', 'g3']) {
        coordinator.onPeerJoined(g);
        coordinator.onPeerStatus(g, const PeerStatus(ready: true, buffering: false, positionMs: 0));
      }
      player.becomeReady();
      async.elapse(const Duration(seconds: 2)); // playing
      player.advancePosition(102000);

      // g1 stalls at 100s; past the stall grace the room waits for it there.
      coordinator.onPeerStatus('g1', const PeerStatus(ready: true, buffering: true, positionMs: 100000));
      async.elapse(const Duration(milliseconds: 2600));
      expect(broadcasts.last.phase, PlaybackPhase.waitingForPeers);
      expect(hostSeeks.last, 100000, reason: 'the rendezvous: the host goes to the stalled guest');

      // g2 follows the room there: seeking, it reports buffering at 100s.
      coordinator.onPeerStatus('g2', const PeerStatus(ready: true, buffering: true, positionMs: 100000));

      // g3 rewinds to 95s (its own buffering already reported, before the wait).
      coordinator.onControlRequest('g3', const ControlRequest(ControlRequestKind.seek, positionMs: 95000));
      expect(hostSeeks.last, 95000);

      // g2's seek to the old spot lands, and it says so.
      coordinator.onPeerStatus('g2', const PeerStatus(ready: true, buffering: false, positionMs: 100000));
      async.elapse(const Duration(milliseconds: 100));
      expect(hostSeeks.last, 95000, reason: "the rewind stands: g2 is on its way to a spot that's gone, not where the room is");
      expect(broadcasts.last.anchorPositionMs, 95000);

      // Everyone comes back; the room plays from the rewind.
      for (final g in ['g1', 'g2', 'g3']) {
        coordinator.onPeerStatus(g, const PeerStatus(ready: true, buffering: false, positionMs: 95000));
      }
      async.elapse(const Duration(seconds: 3));
      expect(broadcasts.where((b) => b.phase == PlaybackPhase.playing).last.anchorPositionMs, 95000);
      expect(hostSeeks.last, 95000);
      coordinator.stop();
    });
  });
}
