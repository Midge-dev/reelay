enum SyncPlaybackState { idle, buffering, ready, ended }

/// Callback-based port of Kotlin's `SyncedPlayerListener` interface (whose
/// three methods all have empty default bodies — implementers only
/// override what they need). A Dart interface can't default-implement
/// methods, so this is a plain holder of nullable callbacks instead.
class SyncedPlayerListener {
  final void Function(bool playWhenReady, bool isUserRequest)? onPlayWhenReadyChanged;
  final void Function(SyncPlaybackState state)? onPlaybackStateChanged;
  final void Function(int positionMs)? onSeek;

  const SyncedPlayerListener({this.onPlayWhenReadyChanged, this.onPlaybackStateChanged, this.onSeek});
}

/// The abstraction the whole sync engine depends on — a Phase 4b player
/// adapter (video_player or otherwise) implements this. Kept deliberately
/// unbound to any concrete player package until then.
abstract class SyncedPlayer {
  bool get isPlaying;
  int get currentPosition;
  int get duration;
  SyncPlaybackState get playbackState;

  void play();
  void pause();
  void seekTo(int positionMs);

  void addListener(SyncedPlayerListener listener);
  void removeListener(SyncedPlayerListener listener);
}
