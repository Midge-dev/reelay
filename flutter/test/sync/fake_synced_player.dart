import 'package:reelay/sync/synced_player.dart';

/// A minimal in-memory SyncedPlayer for exercising
/// HostPlaybackCoordinator/GuestPlaybackReconciler without a real player
/// package. play()/pause()/seekTo() synchronously notify listeners with
/// isUserRequest=false, matching a programmatic call from the coordinator
/// itself (real player adapters deliver this asynchronously, but the
/// coordinator's own expectedPlayWhenReady guard is what actually
/// distinguishes self-triggered vs. user-triggered changes, not timing).
class FakeSyncedPlayer implements SyncedPlayer {
  bool _isPlaying = false;
  int _currentPosition = 0;
  SyncPlaybackState _playbackState = SyncPlaybackState.idle;
  final List<SyncedPlayerListener> _listeners = [];

  @override
  int duration = 3600000;

  @override
  bool get isPlaying => _isPlaying;

  @override
  int get currentPosition => _currentPosition;

  @override
  SyncPlaybackState get playbackState => _playbackState;

  @override
  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(true, false);
    }
  }

  @override
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    for (final l in List.of(_listeners)) {
      l.onPlayWhenReadyChanged?.call(false, false);
    }
  }

  @override
  void seekTo(int positionMs) {
    _currentPosition = positionMs;
    for (final l in List.of(_listeners)) {
      l.onSeek?.call(positionMs);
    }
  }

  @override
  void addListener(SyncedPlayerListener listener) => _listeners.add(listener);

  @override
  void removeListener(SyncedPlayerListener listener) => _listeners.remove(listener);

  /// Test helper: simulate the underlying player finishing loading.
  void becomeReady() {
    _playbackState = SyncPlaybackState.ready;
    for (final l in List.of(_listeners)) {
      l.onPlaybackStateChanged?.call(SyncPlaybackState.ready);
    }
  }

  /// Test helper: simulate the underlying player entering/leaving buffering.
  void setBuffering(bool buffering) {
    _playbackState = buffering ? SyncPlaybackState.buffering : SyncPlaybackState.ready;
    for (final l in List.of(_listeners)) {
      l.onPlaybackStateChanged?.call(_playbackState);
    }
  }

  /// Test helper: move the clock forward without going through seekTo (so
  /// it doesn't fire onSeek), simulating normal playback progress.
  void advancePosition(int deltaMs) => _currentPosition += deltaMs;
}
