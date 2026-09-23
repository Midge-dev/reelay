enum SyncPlaybackState { idle, buffering, ready, ended }

/// What a synced player reports: a plain holder of nullable callbacks, so
/// a listener only supplies the ones it needs.
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
