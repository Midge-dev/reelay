import 'dart:async';

import 'package:video_player/video_player.dart';

import '../sync/synced_player.dart';

/// `SyncedPlayer` backed by `video_player`. Two platform limits, both
/// checked against `video_player`'s actual source:
///
/// - **No playWhenReady, only isPlaying.** ExoPlayer reports *why*
///   `playWhenReady` changed; `video_player` forwards only ExoPlayer's
///   `onIsPlayingChanged` — and ExoPlayer's `isPlaying` is false whenever
///   it's buffering, though it still means to play. Passed on as is, every
///   rebuffer looked like the user pressing pause and then play, and in a
///   Watch Together room each fake press went out to everyone: a host's
///   play hit a buffer, "paused" the room, "played" it again, and its own
///   start-up seek rebuffered it again — a loop (trace
///   test/sync/traces/2026-11-19-pause-loop). So this adapter keeps
///   playWhenReady itself: it changes on [play]/[pause] (every press from
///   the remote and every call the sync logic makes goes through them),
///   on the end of the video, and when the platform stops playback for a
///   reason of its own (another app taking audio focus) — an `isPlaying`
///   false that isn't buffering and lasts [platformStopGrace]. A flip
///   that buffering explains is ignored. Changes are reported with
///   `isUserRequest: true`; [HostPlaybackCoordinator] and
///   [GuestPlaybackReconciler] filter out their own calls with their
///   `_expectPlayWhenReady` window, not with this flag.
/// - **No seek/position-discontinuity event at all** (`VideoEventType` has
///   no such case — checked directly in the platform interface source).
///   But every seek in this app, whether the sync coordinator's own
///   (already self-suppressed the same way as above) or a real one from
///   the controls bar, goes through this adapter's own [seekTo] — so there
///   is no scenario where a seek happens that this adapter didn't itself
///   just perform. [onSeek] is fired synchronously from [seekTo] rather
///   than inferred from position polling.
class VideoPlayerSyncedPlayer implements SyncedPlayer {
  VideoPlayerSyncedPlayer(this.controller);

  final VideoPlayerController controller;

  /// How long the platform's `isPlaying` must stay false, without
  /// buffering, before it counts as playback stopping. ExoPlayer can report
  /// `isPlaying` false a moment before it reports buffering.
  static const platformStopGrace = Duration(milliseconds: 600);

  final _listeners = <SyncedPlayerListener>[];
  bool _playWhenReady = false;
  Timer? _platformStopCheck;
  SyncPlaybackState _lastPlaybackState = SyncPlaybackState.idle;

  /// Whether playback is meant to be running — true through a rebuffer.
  @override
  bool get isPlaying => _playWhenReady;

  @override
  int get currentPosition => controller.value.position.inMilliseconds;

  @override
  int get duration => controller.value.duration.inMilliseconds;

  @override
  SyncPlaybackState get playbackState => _derivePlaybackState(controller.value);

  @override
  void play() {
    _setPlayWhenReady(true);
    controller.play();
  }

  @override
  void pause() {
    _setPlayWhenReady(false);
    controller.pause();
  }

  @override
  void seekTo(int positionMs) {
    controller.seekTo(Duration(milliseconds: positionMs));
    for (final listener in List<SyncedPlayerListener>.of(_listeners)) {
      listener.onSeek?.call(positionMs);
    }
  }

  @override
  void addListener(SyncedPlayerListener listener) {
    if (_listeners.isEmpty) {
      _playWhenReady = controller.value.isPlaying;
      _lastPlaybackState = _derivePlaybackState(controller.value);
      controller.addListener(_handleControllerChange);
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(SyncedPlayerListener listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      controller.removeListener(_handleControllerChange);
      _cancelPlatformStopCheck();
    }
  }

  void _setPlayWhenReady(bool playWhenReady) {
    _cancelPlatformStopCheck();
    if (playWhenReady == _playWhenReady) return;
    _playWhenReady = playWhenReady;
    for (final listener in List<SyncedPlayerListener>.of(_listeners)) {
      listener.onPlayWhenReadyChanged?.call(playWhenReady, true);
    }
  }

  void _cancelPlatformStopCheck() {
    _platformStopCheck?.cancel();
    _platformStopCheck = null;
  }

  /// Whether the platform has stopped playing for a reason other than
  /// buffering or a call through this adapter.
  bool _platformStopped(VideoPlayerValue value) => _playWhenReady && !value.isPlaying && !value.isBuffering;

  void _handleControllerChange() {
    final value = controller.value;

    if (_playWhenReady && value.isCompleted) {
      _setPlayWhenReady(false);
    } else if (!_platformStopped(value)) {
      _cancelPlatformStopCheck();
    } else {
      _platformStopCheck ??= Timer(platformStopGrace, () {
        _platformStopCheck = null;
        if (!_platformStopped(controller.value)) return;
        // Settle the controller on paused too, so it doesn't start again
        // by itself when the platform would let it (focus coming back).
        pause();
      });
    }

    final state = _derivePlaybackState(value);
    if (state != _lastPlaybackState) {
      _lastPlaybackState = state;
      for (final listener in List<SyncedPlayerListener>.of(_listeners)) {
        listener.onPlaybackStateChanged?.call(state);
      }
    }
  }
}

SyncPlaybackState _derivePlaybackState(VideoPlayerValue value) {
  if (!value.isInitialized) return SyncPlaybackState.idle;
  if (value.isCompleted) return SyncPlaybackState.ended;
  if (value.isBuffering) return SyncPlaybackState.buffering;
  return SyncPlaybackState.ready;
}
