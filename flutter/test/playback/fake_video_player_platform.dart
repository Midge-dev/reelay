import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart' show SizedBox, Widget;

import 'package:flutter/services.dart' show PlatformException;

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A minimal fake `VideoPlayerPlatform` for testing [VideoPlayerSyncedPlayer]
/// without a real native video backend. Auto-fires a `VideoEventType.
/// initialized` event as soon as the controller subscribes to
/// [videoEventsFor] (mimicking a real platform's async init completing),
/// so `VideoPlayerController.initialize()` resolves deterministically.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({
    this.audioTracks = const [],
    this.initialDuration = const Duration(minutes: 100),
    this.failInit = false,
    this.failInitWhere,
  });

  final Duration initialDuration;

  /// Fail `initialize()` the way a stream the platform can't open does.
  final bool failInit;

  /// Fail `initialize()` only for sources matching this (e.g. direct play
  /// but not transcode).
  final bool Function(String uri)? failInitWhere;

  /// What getAudioTracks reports; selectAudioTrack moves the selection.
  List<VideoAudioTrack> audioTracks;

  /// Every source opened, in order.
  final openedUris = <String>[];
  final calls = <String>[];

  int _nextPlayerId = 0;
  final _eventControllers = <int, StreamController<VideoEvent>>{};

  /// Each player's position, as getPosition reports it — a reopened stream
  /// starts again from 0 like a real one. Tests move it with [setPosition].
  final _positions = <int, Duration>{};

  /// The most recently opened player.
  int get latestPlayerId => _nextPlayerId - 1;

  /// The player is now at [position] (playback moved on), without a seek.
  void setPosition(int playerId, Duration position) => _positions[playerId] = position;

  /// Seeks each player was asked for, by player id, in order.
  final seeksByPlayer = <int, List<int>>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    final uri = options.dataSource.uri ?? '';
    openedUris.add(uri);
    final fail = failInit || (failInitWhere?.call(uri) ?? false);
    late final StreamController<VideoEvent> controller;
    controller = StreamController<VideoEvent>.broadcast(
      onListen: () => fail
          ? controller.addError(PlatformException(code: 'VideoError', message: 'Source error'))
          : controller.add(VideoEvent(
              eventType: VideoEventType.initialized,
              duration: initialDuration,
              size: const Size(1920, 1080),
            )),
    );
    _eventControllers[id] = controller;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _eventControllers[playerId]!.stream;

  void emit(int playerId, VideoEvent event) => _eventControllers[playerId]!.add(event);

  /// A playback error on a running player, as the platform reports one.
  void emitError(int playerId) =>
      _eventControllers[playerId]!.addError(PlatformException(code: 'VideoError', message: 'Source error'));

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async => audioTracks;

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {
    calls.add('selectAudioTrack:$trackId');
    audioTracks = [
      for (final t in audioTracks)
        VideoAudioTrack(id: t.id, label: t.label, language: t.language, isSelected: t.id == trackId),
    ];
  }

  /// A widget test that mounts a playing [VideoPlayer] needs a view.
  @override
  Widget buildView(int playerId) => const SizedBox();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    seeksByPlayer.putIfAbsent(playerId, () => []).add(position.inMilliseconds);
    calls.add('seekTo:${position.inMilliseconds}');
  }

  @override
  Future<Duration> getPosition(int playerId) async => _positions[playerId] ?? Duration.zero;

  // Deliberately does not close the per-player StreamController: closing a
  // broadcast StreamController that had a listener attach-then-cancel was
  // observed to hang specifically at test-to-test transitions under
  // AutomatedTestWidgetsFlutterBinding (reproduced with a bare
  // StreamController, no video_player code involved — see
  // project_flutter_full_conversion.md). Harmless to leave open here: this
  // is a throwaway per-test fake, not production resource management.
  @override
  Future<void> dispose(int playerId) async {
    _eventControllers.remove(playerId);
  }
}
