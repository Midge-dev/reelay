import 'synced_player.dart';
import 'time_utils.dart';

/// A timestamped record of everything one device's sync engine saw and
/// did during a Watch Together session, one JSON object per entry:
///
/// - `session` — role picked (`host`/`guest`) and this device's peer id
/// - `in` / `out` — a sync relay event received / sent (`event` is its wire
///   JSON). Chat and presence are left out: they don't drive playback, and
///   chat is people's words.
/// - `call` — the sync engine itself told the player to `play`, `pause` or
///   `seekTo`
/// - `player` — the player reported `playWhenReady`, `state` or `seek`. A
///   `seek` with no `call seekTo` just before it was the person's own.
/// - `sample` — once a second: position, playing, player state, and on a
///   guest the clock offset/RTT it's using
///
/// Times are this device's own clock (`t`, ms since epoch). The same format
/// comes out of the room simulation in tests, and `test/sync/sim/` reads
/// it back to turn a real session into a test.
class SyncTrace {
  SyncTrace({this.onEntry, this.maxEntries = 50000, int Function()? now}) : _now = now ?? nowMs;

  /// Called with every entry as it's recorded — a file sink, say.
  final void Function(Map<String, Object?> entry)? onEntry;
  final int maxEntries;
  final int Function() _now;

  final List<Map<String, Object?>> entries = [];

  void record(String type, [Map<String, Object?> data = const {}]) {
    final entry = <String, Object?>{'t': _now(), 'type': type, ...data};
    entries.add(entry);
    if (entries.length > maxEntries) entries.removeRange(0, entries.length - maxEntries);
    onEntry?.call(entry);
  }
}

/// Passes everything through to [inner], recording to [trace] the calls the
/// sync engine makes (`call`) and what the player reports (`player`).
///
/// The sync engine is handed this wrapper and the player screen keeps the
/// raw player, so a `call` is always the engine's and a `player` event with
/// no matching `call` is the person's own.
class TracingSyncedPlayer implements SyncedPlayer {
  TracingSyncedPlayer(this.inner, this.trace) {
    // Added first, so each report is recorded before anything reacts to it.
    inner.addListener(_recorder);
  }

  final SyncedPlayer inner;
  final SyncTrace trace;

  late final SyncedPlayerListener _recorder = SyncedPlayerListener(
    onPlayWhenReadyChanged: (playWhenReady, _) =>
        trace.record('player', {'ev': 'playWhenReady', 'value': playWhenReady, 'pos': inner.currentPosition}),
    onPlaybackStateChanged: (state) =>
        trace.record('player', {'ev': 'state', 'value': state.name, 'pos': inner.currentPosition}),
    onSeek: (positionMs) => trace.record('player', {'ev': 'seek', 'value': positionMs}),
  );

  /// Stops recording; the inner player carries on.
  void detach() => inner.removeListener(_recorder);

  @override
  bool get isPlaying => inner.isPlaying;
  @override
  int get currentPosition => inner.currentPosition;
  @override
  int get duration => inner.duration;
  @override
  SyncPlaybackState get playbackState => inner.playbackState;

  @override
  void play() {
    trace.record('call', {'op': 'play', 'pos': inner.currentPosition});
    inner.play();
  }

  @override
  void pause() {
    trace.record('call', {'op': 'pause', 'pos': inner.currentPosition});
    inner.pause();
  }

  @override
  void seekTo(int positionMs) {
    trace.record('call', {'op': 'seekTo', 'value': positionMs, 'pos': inner.currentPosition});
    inner.seekTo(positionMs);
  }

  @override
  void setPlaybackRate(double rate) {
    trace.record('call', {'op': 'rate', 'value': rate, 'pos': inner.currentPosition});
    inner.setPlaybackRate(rate);
  }

  @override
  void addListener(SyncedPlayerListener listener) => inner.addListener(listener);
  @override
  void removeListener(SyncedPlayerListener listener) => inner.removeListener(listener);
}
