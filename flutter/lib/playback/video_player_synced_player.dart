import 'package:video_player/video_player.dart';

import '../sync/synced_player.dart';

/// `SyncedPlayer` backed by `video_player`. Two platform limits, both
/// checked against `video_player`'s actual source:
///
/// - **No reason codes for play/pause changes.** ExoPlayer reports *why*
///   `playWhenReady` changed (`PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST`
///   vs. audio-focus-loss, etc.); `video_player`'s `VideoPlayerValue` only
///   reports the new `isPlaying`, with no reason. In practice this doesn't
///   cost anything: a "user request" just means "the app explicitly
///   called play()/pause()" — which is true of every
///   `isPlaying` change this adapter can observe, since nothing besides an
///   explicit call (ours or the platform's own, e.g. another app briefly
///   taking audio focus) changes it. So `isUserRequest` is always reported
///   `true` here; [HostPlaybackCoordinator]/[GuestPlaybackReconciler]
///   already filter out their *own* triggered changes via their
///   `_expectPlayWhenReady` self-suppression window, not via this flag.
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

  final _listeners = <SyncedPlayerListener>[];
  bool _lastIsPlaying = false;
  SyncPlaybackState _lastPlaybackState = SyncPlaybackState.idle;

  @override
  bool get isPlaying => controller.value.isPlaying;

  @override
  int get currentPosition => controller.value.position.inMilliseconds;

  @override
  int get duration => controller.value.duration.inMilliseconds;

  @override
  SyncPlaybackState get playbackState => _derivePlaybackState(controller.value);

  @override
  void play() => controller.play();

  @override
  void pause() => controller.pause();

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
      _lastIsPlaying = controller.value.isPlaying;
      _lastPlaybackState = _derivePlaybackState(controller.value);
      controller.addListener(_handleControllerChange);
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(SyncedPlayerListener listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) controller.removeListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    final value = controller.value;

    final isPlaying = value.isPlaying;
    if (isPlaying != _lastIsPlaying) {
      _lastIsPlaying = isPlaying;
      for (final listener in List<SyncedPlayerListener>.of(_listeners)) {
        listener.onPlayWhenReadyChanged?.call(isPlaying, true);
      }
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
