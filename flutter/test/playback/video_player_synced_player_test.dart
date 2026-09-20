import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/playback/video_player_synced_player.dart';
import 'package:reelay/sync/synced_player.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_player_platform.dart';

// Deliberately never calls controller.dispose(): VideoPlayerController's
// own dispose() (specifically its internal _eventSubscription.cancel())
// was reproduced hanging under AutomatedTestWidgetsFlutterBinding with a
// bare StreamController.broadcast(onListen: ...) too — nothing specific
// to this adapter or fake (see project_flutter_full_conversion.md). Each
// test gets a fresh controller/fake; the leaked controller is harmless
// within a single isolated flutter_test process.
Future<VideoPlayerController> _initializedController(FakeVideoPlayerPlatform fake) async {
  VideoPlayerPlatform.instance = fake;
  final controller = VideoPlayerController.networkUrl(Uri.parse('http://example.com/video.mp4'));
  await controller.initialize();
  return controller;
}

void main() {
  group('basic getters', () {
    testWidgets('delegate to the underlying controller', (tester) async {
      final fake = FakeVideoPlayerPlatform(initialDuration: const Duration(minutes: 2));
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      expect(player.duration, const Duration(minutes: 2).inMilliseconds);
      expect(player.currentPosition, 0);
      expect(player.isPlaying, isFalse);
      expect(player.playbackState, SyncPlaybackState.ready);
    });
  });

  group('play/pause', () {
    testWidgets('play() delegates to the controller and reports isUserRequest: true', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      bool? reportedPlaying;
      bool? reportedUserRequest;
      player.addListener(SyncedPlayerListener(
        onPlayWhenReadyChanged: (playWhenReady, isUserRequest) {
          reportedPlaying = playWhenReady;
          reportedUserRequest = isUserRequest;
        },
      ));

      player.play();
      await tester.pump();
      await tester.pump();

      expect(fake.calls, contains('play'));
      expect(reportedPlaying, isTrue);
      expect(reportedUserRequest, isTrue);

      // play() starts VideoPlayerController's own 100ms position-polling
      // Timer.periodic; pause() to stop it before the test ends, or the
      // binding's end-of-test "no pending timers" check fails.
      player.pause();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('pause() delegates to the controller and reports isUserRequest: true', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);
      player.play();
      await tester.pump();
      await tester.pump();

      bool? reportedPlaying;
      player.addListener(SyncedPlayerListener(onPlayWhenReadyChanged: (playWhenReady, _) => reportedPlaying = playWhenReady));

      player.pause();
      await tester.pump();
      await tester.pump();

      expect(fake.calls, contains('pause'));
      expect(reportedPlaying, isFalse);
    });

    testWidgets('a no-op removeListener before any add is safe', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      expect(() => player.removeListener(const SyncedPlayerListener()), returnsNormally);
    });

    testWidgets('a removed listener stops receiving callbacks', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      var calls = 0;
      final listener = SyncedPlayerListener(onPlayWhenReadyChanged: (_, _) => calls++);
      player.addListener(listener);
      player.removeListener(listener);

      player.play();
      await tester.pump();
      await tester.pump();

      expect(calls, 0);

      player.pause();
      await tester.pump();
      await tester.pump();
    });
  });

  group('seekTo', () {
    testWidgets('delegates to the controller and fires onSeek synchronously', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      int? reportedPositionMs;
      player.addListener(SyncedPlayerListener(onSeek: (positionMs) => reportedPositionMs = positionMs));

      player.seekTo(30000);

      expect(fake.calls, contains('seekTo:30000'));
      expect(reportedPositionMs, 30000, reason: 'onSeek fires synchronously from seekTo, not via polling');
    });
  });

  group('playback state', () {
    testWidgets('buffering start/end is reported via onPlaybackStateChanged', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      final states = <SyncPlaybackState>[];
      player.addListener(SyncedPlayerListener(onPlaybackStateChanged: states.add));

      fake.emit(0, VideoEvent(eventType: VideoEventType.bufferingStart));
      await tester.pump();
      fake.emit(0, VideoEvent(eventType: VideoEventType.bufferingEnd));
      await tester.pump();

      expect(states, [SyncPlaybackState.buffering, SyncPlaybackState.ready]);
    });

    testWidgets('duplicate state notifications are not re-reported', (tester) async {
      final fake = FakeVideoPlayerPlatform();
      final controller = await _initializedController(fake);
      final player = VideoPlayerSyncedPlayer(controller);

      final states = <SyncPlaybackState>[];
      player.addListener(SyncedPlayerListener(onPlaybackStateChanged: states.add));

      fake.emit(0, VideoEvent(eventType: VideoEventType.bufferingUpdate, buffered: const []));
      await tester.pump();

      expect(states, isEmpty, reason: 'a buffered-range update alone does not change ready/buffering/ended');
    });
  });
}
