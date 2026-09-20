import 'dart:async';

import 'playback_state.dart';
import 'synced_player.dart';
import 'time_utils.dart';

/// Host-side state machine for watch-together playback — not just a relay,
/// a real coordinator. Ports HostPlaybackCoordinator.kt with every timing
/// constant unchanged (guests, and any other host implementation, must
/// agree on these to interoperate). Kotlin gets "every scheduled callback
/// stops firing once this is torn down" for free from structured
/// concurrency (cancelling `scope` cancels every child job, tracked or
/// not); Dart Timers don't have that, so every scheduled callback here
/// checks `_disposed` even where the Kotlin source doesn't explicitly —
/// that's restoring behavioral parity, not added scope.
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

  int _seq = 0;
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
  final Map<String, PeerStatus> _peerStatuses = {};
  final Set<String> _stalledPeers = {};
  final Set<String> _excused = {};
  final Map<String, Timer> _peerStallGraceTimers = {};
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
      if (_isSeekSuppressed()) return;
      _afterHostSeek(positionMs, myPeerId);
    },
  );

  bool _isSeekSuppressed() => nowMs() < _suppressSeekUntilMs;

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
    if (status.ready && !status.buffering) _excused.remove(peerId);

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
            _enterWaiting();
          });
        });
      } else if (_phase == PlaybackPhase.waitingForPeers && !_stalledPeers.contains(peerId)) {
        _stalledPeers.add(peerId);
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
    _peerStatuses.remove(peerId);
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
      _selfStallGraceTimer = Timer(Duration(milliseconds: _stallGraceMs), () {
        if (_disposed) return;
        if (!_localBuffering || _phase != PlaybackPhase.playing) return;
        _localStalled = true;
        _enterWaiting();
      });
    } else if (_localStalled) {
      _localStalled = false;
      _scheduleAllReadyCheck(_recoveryHysteresisMs);
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
        if (!_firstStartCompleted) gating.add(peerId);
        continue;
      }
      if (_stalledPeers.contains(peerId)) gating.add(peerId);
    }
    if (!_localReady || _localStalled) gating.add(myPeerId);
    return gating;
  }

  void _enterWaiting() {
    if (_phase == PlaybackPhase.waitingForPeers) return;
    if (!_localStalled) _setPaused();
    _intendedPlaying = true;
    _setPhase(PlaybackPhase.waitingForPeers);
    _broadcast();
    _armSafetyIfGated();
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
      _scheduleStart(_pendingActor ?? myPeerId);
    } else {
      _setPhase(PlaybackPhase.paused);
      _broadcast();
    }
    _pendingActor = null;
  }

  void _scheduleStart(String actor) {
    _cancelPendingStart();
    final otherPeers = _knownPeers.difference(_excused);
    final delayMs = otherPeers.isEmpty ? 0 : _startDelayMs;
    final startAt = nowMs() + delayMs;
    final startPositionMs = player.currentPosition;
    _firstStartCompleted = true;
    _setPhase(PlaybackPhase.playing);
    _broadcast(
      hint: PlaybackActionHint.play,
      actor: actor,
      anchorOverrideMs: startPositionMs,
      anchorHostTimeOverrideMs: startAt,
    );

    if (delayMs <= 0 && player.isPlaying) return;

    _pendingStartTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_disposed || _phase != PlaybackPhase.playing) return;
      if ((player.currentPosition - startPositionMs).abs() > 250) {
        _suppressedSeek(() => player.seekTo(startPositionMs));
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
      _stalledPeers.removeAll(gating);
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
    final last = _lastBroadcast;
    PlaybackActionHint? hint;
    if (last != null && _pendingStartTimer == null) {
      final expected = last.targetPositionMs(nowMs());
      if ((player.currentPosition - expected).abs() > _implicitJumpThresholdMs) hint = PlaybackActionHint.seek;
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
    final anchorPositionMs = anchorOverrideMs ?? player.currentPosition;
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
