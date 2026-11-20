import 'dart:async';

import 'playback_state.dart';
import 'synced_player.dart';
import 'time_utils.dart';

/// Host-side state machine for watch-together playback — not just a relay,
/// a real coordinator. Its timing constants are part of the protocol:
/// guests, and any other host implementation, must agree on them. Dart
/// Timers don't stop on their own when this is torn down, so every
/// scheduled callback checks `_disposed`.
class HostPlaybackCoordinator {
  static const _stallGraceMs = 2500;
  static const _recoveryHysteresisMs = 800;
  static const _safetyTimeoutMs = 15000;
  static const _heartbeatPlayingMs = 2000;
  static const _heartbeatIdleMs = 5000;
  static const _startDelayMs = 750;
  static const _implicitJumpThresholdMs = 1500;
  static const _seekSuppressionWindowMs = 400;
  static const _expectationTimeoutMs = 3000;
  // Guests re-seek while stopped once they're more than 500ms off (see
  // GuestPlaybackReconciler._pausedSeekThresholdMs), so the room only moves
  // to a stalled peer when it's further out than that — and never drags
  // everyone back further than a couple of minutes for one peer.
  static const _rendezvousToleranceMs = 500;
  static const _rendezvousMaxMs = 120000;

  final String myPeerId;
  final SyncedPlayer player;
  final void Function(PlaybackState state) sendState;
  final void Function(List<String> waitingOn) onWaitingOnChanged;

  HostPlaybackCoordinator({
    required this.myPeerId,
    required this.player,
    required this.sendState,
    this.onWaitingOnChanged = _noop,
  });

  static void _noop(List<String> _) {}

  // Guests drop any state whose seq isn't above the last one they took. A
  // new coordinator (PlayerScreen makes one per stream: every subtitle,
  // quality or audio change) counting from 0 again was ignored until it
  // overtook the old count — after an hour's watching, for about another
  // hour. Starting from the clock keeps every coordinator on this device
  // above the last; states go out far less often than once a millisecond.
  int _seq = nowMs();
  PlaybackPhase _phase = PlaybackPhase.loading;
  bool _intendedPlaying = true;
  bool _localReady = false;
  bool _localBuffering = false;
  bool _localStalled = false;
  bool _firstStartCompleted = false;
  int _suppressSeekUntilMs = 0;
  bool? _expectedPlayWhenReady;
  int _expectedPlayWhenReadySetAtMs = 0;
  bool _disposed = false;

  final Set<String> _knownPeers = {};

  /// Everyone this host has heard from and not seen leave.
  Set<String> get knownPeers => Set.unmodifiable(_knownPeers);
  final Map<String, PeerStatus> _peerStatuses = {};
  final Set<String> _stalledPeers = {};
  final Set<String> _excused = {};
  /// Peers that stalled since the room last started playing: the room
  /// resumes from where they are, not from where the host got to.
  final Set<String> _stalledSinceStart = {};
  final Map<String, Timer> _peerStallGraceTimers = {};

  /// Peers that arrived after the room had started, not yet ready: the room
  /// holds for them where it is, so they join in on the same frame rather
  /// than chasing a room that plays on without them.
  final Set<String> _lateJoiners = {};
  Timer? _selfStallGraceTimer;

  Timer? _pendingStartTimer;
  Timer? _safetyTimer;
  Timer? _heartbeatTimer;
  Timer? _allReadyCheckTimer;

  PlaybackState? _lastBroadcast;
  String? _pendingActor;

  late final SyncedPlayerListener _listener = SyncedPlayerListener(
    onPlayWhenReadyChanged: (playWhenReady, isUserRequest) {
      if (_consumeExpectedPlayWhenReady(playWhenReady)) return;
      if (!isUserRequest) return;
      if (playWhenReady) {
        _requestPlay(myPeerId);
      } else {
        _requestPause(myPeerId);
      }
    },
    onPlaybackStateChanged: (state) {
      if (state == SyncPlaybackState.ready && !_localReady) {
        _localReady = true;
        _onLocalLoaded();
        return;
      }
      if (!_localReady) return;
      final buffering = state == SyncPlaybackState.buffering;
      if (buffering == _localBuffering) return;
      _localBuffering = buffering;
      _onSelfBuffering(buffering);
    },
    onSeek: (positionMs) {
      _seekTargetMs = positionMs;
      _seekTargetAtMs = _lastSeekAtMs = nowMs();
      if (_isSeekSuppressed()) return;
      _afterHostSeek(positionMs, myPeerId);
    },
  );

  bool _isSeekSuppressed() => nowMs() < _suppressSeekUntilMs;

  // A real player reports its old position for a moment after a seek (see
  // VideoPlayerSyncedPlayer: video_player updates it once the platform call
  // returns). Until it catches up, the host's position is the seek target.
  static const _seekReportGraceMs = 1000;
  int? _seekTargetMs;
  int _seekTargetAtMs = 0;
  int _lastSeekAtMs = -_seekReportGraceMs;

  int get _positionMs {
    final target = _seekTargetMs;
    if (target == null) return player.currentPosition;
    if ((player.currentPosition - target).abs() <= 250 || nowMs() - _seekTargetAtMs > _seekReportGraceMs) {
      _seekTargetMs = null;
      return player.currentPosition;
    }
    return target;
  }

  void _suppressedSeek(void Function() block) {
    _suppressSeekUntilMs = nowMs() + _seekSuppressionWindowMs;
    block();
  }

  void _expectPlayWhenReady(bool target) {
    _expectedPlayWhenReady = target;
    _expectedPlayWhenReadySetAtMs = nowMs();
  }

  bool _consumeExpectedPlayWhenReady(bool playWhenReady) {
    if (_expectedPlayWhenReady == playWhenReady && nowMs() - _expectedPlayWhenReadySetAtMs <= _expectationTimeoutMs) {
      _expectedPlayWhenReady = null;
      return true;
    }
    return false;
  }

  void _setPaused() {
    if (player.isPlaying) {
      _expectPlayWhenReady(false);
      player.pause();
    }
  }

  void _setPlaying() {
    if (!player.isPlaying) {
      _expectPlayWhenReady(true);
      player.play();
    }
  }

  void start() {
    player.addListener(_listener);
    _localReady = player.playbackState == SyncPlaybackState.ready;
    if (_localReady) {
      _onLocalLoaded();
    } else {
      _setPhase(PlaybackPhase.loading);
    }
    _restartHeartbeat();
  }

  void stop() {
    _disposed = true;
    player.removeListener(_listener);
    _pendingStartTimer?.cancel();
    _safetyTimer?.cancel();
    _heartbeatTimer?.cancel();
    _allReadyCheckTimer?.cancel();
    _selfStallGraceTimer?.cancel();
    for (final timer in _peerStallGraceTimers.values) {
      timer.cancel();
    }
    _peerStallGraceTimers.clear();
  }

  void onPeerJoined(String peerId) {
    if (peerId == myPeerId) return;
    _knownPeers.add(peerId);
    _broadcast();
  }

  void onPeerStatus(String peerId, PeerStatus status) {
    if (peerId == myPeerId) return;
    _knownPeers.add(peerId);
    final previous = _peerStatuses[peerId];
    _peerStatuses[peerId] = status;
    if (status.ready && !status.buffering) {
      _excused.remove(peerId);
      _lateJoiners.remove(peerId);
    }
    if (previous == null && !status.ready && _firstStartCompleted) {
      _lateJoiners.add(peerId);
      if (_phase == PlaybackPhase.playing) _enterWaiting();
    }
    // A peer the room is waiting for has moved (its seek landed somewhere
    // else, or it re-seeked): wait for it there instead.
    if (_phase == PlaybackPhase.waitingForPeers && _stalledSinceStart.contains(peerId)) {
      final moved = _rendezvous();
      if (moved != null) _broadcast(anchorOverrideMs: moved);
    }

    if (status.ready && status.buffering) {
      if (_phase == PlaybackPhase.playing && !_stalledPeers.contains(peerId)) {
        _peerStallGraceTimers.putIfAbsent(peerId, () {
          return Timer(Duration(milliseconds: _stallGraceMs), () {
            if (_disposed) return;
            _peerStallGraceTimers.remove(peerId);
            final latest = _peerStatuses[peerId];
            if (latest == null) return;
            if (!latest.buffering || _phase != PlaybackPhase.playing) return;
            _stalledPeers.add(peerId);
            _stalledSinceStart.add(peerId);
            _enterWaiting();
          });
        });
      } else if (_phase == PlaybackPhase.waitingForPeers && !_stalledPeers.contains(peerId)) {
        _stalledPeers.add(peerId);
        _stalledSinceStart.add(peerId);
        _scheduleAllReadyCheck(0);
      }
    } else {
      _peerStallGraceTimers.remove(peerId)?.cancel();
      final wasStalled = _stalledPeers.remove(peerId);
      final becameReady = status.ready && (previous == null || !previous.ready);
      if (wasStalled) {
        _scheduleAllReadyCheck(_recoveryHysteresisMs);
      } else if (becameReady) {
        _scheduleAllReadyCheck(0);
      }
    }
  }

  void onPeerLeft(String peerId) {
    _knownPeers.remove(peerId);
    _excused.remove(peerId);
    _stalledPeers.remove(peerId);
    _stalledSinceStart.remove(peerId);
    _peerStatuses.remove(peerId);
    _lateJoiners.remove(peerId);
    _peerStallGraceTimers.remove(peerId)?.cancel();
    _scheduleAllReadyCheck(0);
  }

  void onControlRequest(String peerId, ControlRequest request) {
    switch (request.kind) {
      case ControlRequestKind.play:
        _requestPlay(peerId);
      case ControlRequestKind.pause:
        _requestPause(peerId);
      case ControlRequestKind.seek:
        final positionMs = request.positionMs;
        if (positionMs != null) _applyRemoteSeek(positionMs, peerId);
    }
  }

  void _onLocalLoaded() {
    if (_phase == PlaybackPhase.loading) {
      _setPaused();
      _setPhase(PlaybackPhase.waitingForPeers);
      _broadcast();
      _armSafetyIfGated();
    }
    _scheduleAllReadyCheck(0);
  }

  void _onSelfBuffering(bool buffering) {
    if (buffering) {
      if (_phase != PlaybackPhase.playing || _localStalled) return;
      // Buffering just after a seek is the seek landing, not a hiccup: on a
      // slow stream (a remote transcode) it lasts seconds, and guests would
      // play on ahead of the host for the whole grace.
      if (nowMs() - _lastSeekAtMs < _seekReportGraceMs) {
        _localStalled = true;
        _enterWaiting();
        return;
      }
      _selfStallGraceTimer = Timer(Duration(milliseconds: _stallGraceMs), () {
        if (_disposed) return;
        if (!_localBuffering || _phase != PlaybackPhase.playing) return;
        _localStalled = true;
        _enterWaiting();
      });
    } else if (_localStalled) {
      _localStalled = false;
      // The host stayed "playing" through its own stall so it could carry
      // on the moment it recovered — but if the room is still waiting, it
      // must hold where it is, not play on ahead of everyone.
      if (_phase == PlaybackPhase.waitingForPeers) _setPaused();
      _scheduleAllReadyCheck(_recoveryHysteresisMs);
    } else if (_phase == PlaybackPhase.waitingForPeers) {
      _scheduleAllReadyCheck(0);
    }
  }

  void _requestPlay(String actor) {
    if (_phase == PlaybackPhase.playing) return;
    _intendedPlaying = true;
    _pendingActor = actor;
    if (!_localReady) {
      _setPaused();
      return;
    }
    final gating = _gatingPeers();
    if (gating.isEmpty) {
      _scheduleStart(actor);
    } else {
      _setPaused();
      if (_phase != PlaybackPhase.waitingForPeers) {
        _setPhase(PlaybackPhase.waitingForPeers);
        _broadcast(actor: actor);
        _armSafetyIfGated();
      }
    }
  }

  void _requestPause(String actor) {
    _intendedPlaying = false;
    _pendingActor = null;
    _stalledSinceStart.clear();
    _cancelPendingStart();
    _cancelSafety();
    _setPaused();
    if (_phase == PlaybackPhase.loading) return;
    _setPhase(PlaybackPhase.paused);
    _broadcast(hint: PlaybackActionHint.pause, actor: actor);
  }

  void _applyRemoteSeek(int targetMs, String actor) {
    final duration = player.duration;
    if (duration <= 0 || targetMs < 0 || targetMs > duration) return;
    _suppressedSeek(() => player.seekTo(targetMs));
    _afterHostSeek(targetMs, actor);
  }

  void _afterHostSeek(int targetMs, String actor) {
    _broadcast(hint: PlaybackActionHint.seek, actor: actor, anchorOverrideMs: targetMs);
  }

  Set<String> _gatingPeers() {
    final gating = <String>{};
    for (final peerId in _knownPeers) {
      if (_excused.contains(peerId)) continue;
      final status = _peerStatuses[peerId];
      if (status == null || !status.ready) {
        if (!_firstStartCompleted || _lateJoiners.contains(peerId)) gating.add(peerId);
        continue;
      }
      if (_stalledPeers.contains(peerId)) gating.add(peerId);
    }
    // While the room's stopped, the host starts no one until its own player
    // is ready to go too.
    if (!_localReady || _localStalled || (_localBuffering && _phase != PlaybackPhase.playing)) gating.add(myPeerId);
    return gating;
  }

  void _enterWaiting() {
    if (_phase == PlaybackPhase.waitingForPeers) return;
    if (!_localStalled) _setPaused();
    _intendedPlaying = true;
    _setPhase(PlaybackPhase.waitingForPeers);
    _broadcast(anchorOverrideMs: _rendezvous());
    _armSafetyIfGated();
  }

  /// Where the room should wait and then resume after a peer stalled.
  ///
  /// A peer only counts as stalled after [_stallGraceMs] of buffering, and
  /// the host keeps playing through that grace — so by the time the room
  /// pauses, the host is seconds ahead of the peer it's waiting for. Pausing
  /// and resuming at the host's spot makes that peer seek again, and a peer
  /// whose seeks are slow (a remote transcode that has to make new segments)
  /// stalls again, the host runs ahead again, and the room loops forever.
  /// So the host goes to the earliest stalled peer instead — usually a step
  /// back, sometimes forward when a guest aimed ahead: the host's own seek is
  /// the cheap one, and the slow peer is already where it needs to be.
  /// Guests don't seek while the room waits on them (see
  /// GuestPlaybackReconciler), so the two never chase each other. Seeks the host itself (suppressed, so it isn't a user seek) and
  /// returns the position to anchor on, or null to stay where it is.
  int? _rendezvous() {
    int? earliest;
    for (final peerId in _stalledSinceStart) {
      if (_excused.contains(peerId)) continue;
      final position = _peerStatuses[peerId]?.positionMs;
      if (position == null) continue;
      if (earliest == null || position < earliest) earliest = position;
    }
    if (earliest == null) return null;
    final offMs = (_positionMs - earliest).abs();
    if (offMs <= _rendezvousToleranceMs || offMs > _rendezvousMaxMs) return null;
    final target = earliest;
    _suppressedSeek(() => player.seekTo(target));
    return target;
  }

  void _scheduleAllReadyCheck(int delayMs) {
    _allReadyCheckTimer?.cancel();
    _allReadyCheckTimer = Timer(Duration(milliseconds: delayMs), _checkAllReady);
  }

  void _checkAllReady() {
    if (_disposed || _phase != PlaybackPhase.waitingForPeers) return;
    final gating = _gatingPeers();
    if (gating.isNotEmpty) {
      _broadcastIfWaitingOnChanged(gating);
      return;
    }
    _resolveAllReady();
  }

  void _resolveAllReady() {
    _cancelSafety();
    if (_intendedPlaying) {
      // The stalled peers' latest statuses (sent as they recovered, while
      // paused) say exactly where they are now.
      _scheduleStart(_pendingActor ?? myPeerId, startPositionMs: _rendezvous());
    } else {
      _setPhase(PlaybackPhase.paused);
      _broadcast();
    }
    _pendingActor = null;
  }

  /// [startPositionMs] is for a position the host just seeked to: a real
  /// player's [SyncedPlayer.currentPosition] can lag a seek it hasn't
  /// finished.
  void _scheduleStart(String actor, {int? startPositionMs}) {
    _cancelPendingStart();
    final otherPeers = _knownPeers.difference(_excused);
    final delayMs = otherPeers.isEmpty ? 0 : _startDelayMs;
    final startAt = nowMs() + delayMs;
    startPositionMs ??= _positionMs;
    _stalledSinceStart.clear();
    _firstStartCompleted = true;
    _setPhase(PlaybackPhase.playing);
    _broadcast(
      hint: PlaybackActionHint.play,
      actor: actor,
      anchorOverrideMs: startPositionMs,
      anchorHostTimeOverrideMs: startAt,
    );

    if (delayMs <= 0 && player.isPlaying) return;
    // A play press starts this player at once, but the room starts
    // [delayMs] from now: left running, it got that far ahead, the start
    // seeked it back, the seek rebuffered, and a rebuffer just after a seek
    // stalls the host — the room waited on its own host before it began.
    if (delayMs > 0) _setPaused();

    final startMs = startPositionMs;
    _pendingStartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_disposed || _phase != PlaybackPhase.playing) return;
      if ((_positionMs - startMs).abs() > 250) {
        _suppressedSeek(() => player.seekTo(startMs));
      }
      _setPlaying();
    });
  }

  void _armSafetyIfGated() {
    _cancelSafety();
    if (_gatingPeers().difference({myPeerId}).isEmpty) return;
    _safetyTimer = Timer(Duration(milliseconds: _safetyTimeoutMs), () {
      if (_disposed) return;
      if (_phase != PlaybackPhase.waitingForPeers) return;
      final gating = _gatingPeers().difference({myPeerId});
      if (gating.isEmpty) return;
      _excused.addAll(gating);
      _lateJoiners.removeAll(gating);
      _stalledPeers.removeAll(gating);
      _stalledSinceStart.removeAll(gating);
      _scheduleAllReadyCheck(0);
    });
  }

  void _cancelPendingStart() {
    _pendingStartTimer?.cancel();
    _pendingStartTimer = null;
  }

  void _cancelSafety() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }

  void _restartHeartbeat() {
    _heartbeatTimer?.cancel();
    final interval = _phase == PlaybackPhase.playing ? _heartbeatPlayingMs : _heartbeatIdleMs;
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: interval), (_) => _onHeartbeat());
  }

  void _onHeartbeat() {
    if (_disposed) return;
    // Just after a seek the host made itself, a real player may still report
    // the old position: wait for the next beat rather than announce it.
    if (_isSeekSuppressed()) return;
    final last = _lastBroadcast;
    PlaybackActionHint? hint;
    if (last != null && _pendingStartTimer == null) {
      final expected = last.targetPositionMs(nowMs());
      if ((_positionMs - expected).abs() > _implicitJumpThresholdMs) hint = PlaybackActionHint.seek;
    }
    _broadcast(hint: hint, actor: hint != null ? myPeerId : null);
  }

  void _broadcastIfWaitingOnChanged(Set<String> gating) {
    final last = _lastBroadcast;
    if (last == null) return;
    final sortedGating = gating.toList()..sort();
    if (_listEquals(sortedGating, last.waitingOn)) return;
    _broadcast();
  }

  void _setPhase(PlaybackPhase newPhase) {
    if (_phase == newPhase) return;
    _phase = newPhase;
    _restartHeartbeat();
  }

  void _broadcast({
    PlaybackActionHint? hint,
    String? actor,
    int? anchorOverrideMs,
    int? anchorHostTimeOverrideMs,
  }) {
    if (_disposed) return;
    final anchorPositionMs = anchorOverrideMs ?? _positionMs;
    final anchorHostTimeMs = anchorHostTimeOverrideMs ?? nowMs();
    final waitingOn = _phase == PlaybackPhase.waitingForPeers ? (_gatingPeers().toList()..sort()) : const <String>[];

    final state = PlaybackState(
      seq: ++_seq,
      phase: _phase,
      anchorPositionMs: anchorPositionMs,
      anchorHostTimeMs: anchorHostTimeMs,
      waitingOn: waitingOn,
      actorPeerId: actor,
      actionHint: hint,
    );
    final previousWaiting = _lastBroadcast?.waitingOn ?? const <String>[];
    _lastBroadcast = state;
    if (!_listEquals(previousWaiting, waitingOn)) onWaitingOnChanged(waitingOn);
    sendState(state);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
