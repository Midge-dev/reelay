import 'dart:async';

import 'clock_sync.dart';
import 'playback_state.dart';
import 'synced_player.dart';
import 'time_utils.dart';

/// Guest-side reconciliation against the host's authoritative PlaybackState.
/// Ports GuestPlaybackReconciler.kt with every timing constant unchanged.
class GuestPlaybackReconciler {
  static const _tickMs = 500;
  static const _deadbandMs = 1500;
  static const _hardSeekCooldownMs = 4000;
  static const _pausedSeekThresholdMs = 500;
  static const _settleTimeoutMs = 1500;
  static const _optimisticWindowMs = 2000;
  static const _seekSuppressionWindowMs = 400;
  static const _expectationTimeoutMs = 3000;
  static const _hostStaleTimeoutMs = 8000;

  final String myPeerId;
  final SyncedPlayer player;
  final ClockSync clock;
  final void Function(ControlRequest request) sendControl;
  final void Function(PeerStatus status) sendStatus;

  GuestPlaybackReconciler({
    required this.myPeerId,
    required this.player,
    required this.clock,
    required this.sendControl,
    required this.sendStatus,
  });

  PlaybackState? _latestState;
  int _lastStateAtMs = 0;
  int _lastSeq = -1;
  bool _localReady = false;
  int _suppressSeekUntilMs = 0;
  bool? _expectedPlayWhenReady;
  int _expectedPlayWhenReadySetAtMs = 0;
  bool _settling = false;
  Timer? _settleTimer;
  int _lastHardSeekMs = -_hardSeekCooldownMs;
  Timer? _tickTimer;
  Timer? _scheduledStartTimer;
  int? _scheduledStartSeq;
  int? _optimisticUntilSeq;
  int _optimisticDeadlineMs = 0;
  PeerStatus? _lastSentStatus;
  bool _disposed = false;

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

  late final SyncedPlayerListener _listener = SyncedPlayerListener(
    onPlayWhenReadyChanged: (playWhenReady, isUserRequest) {
      if (_consumeExpectedPlayWhenReady(playWhenReady)) return;
      if (!isUserRequest) return;
      if (_latestState == null) return;
      sendControl(ControlRequest(playWhenReady ? ControlRequestKind.play : ControlRequestKind.pause));
      _markOptimistic();
    },
    onPlaybackStateChanged: (state) {
      if (state == SyncPlaybackState.ready && !_localReady) {
        _localReady = true;
        _sendStatusNow(force: true);
        _reconcile();
        return;
      }
      _sendStatusNow();
    },
    onSeek: (positionMs) {
      if (_isSeekSuppressed()) return;
      if (_latestState == null) return;
      sendControl(ControlRequest(ControlRequestKind.seek, positionMs: positionMs));
      _markOptimistic();
    },
  );

  void start() {
    player.addListener(_listener);
    _localReady = player.playbackState == SyncPlaybackState.ready;
    clock.start();
    _tickTimer = Timer.periodic(Duration(milliseconds: _tickMs), (_) => _reconcile());
    _sendStatusNow(force: true);
  }

  void stop() {
    _disposed = true;
    player.removeListener(_listener);
    clock.stop();
    _tickTimer?.cancel();
    _settleTimer?.cancel();
    _scheduledStartTimer?.cancel();
    sendStatus(const PeerStatus(ready: false, buffering: false, positionMs: 0));
  }

  void onState(PlaybackState state) {
    if (state.seq <= _lastSeq) return;
    _lastSeq = state.seq;
    _latestState = state;
    _lastStateAtMs = nowMs();

    if (_optimisticUntilSeq != null && (state.actorPeerId == myPeerId || state.actionHint != null)) {
      _optimisticUntilSeq = null;
    }
    if (state.waitingOn.contains(myPeerId) && _localReady && player.playbackState != SyncPlaybackState.buffering) {
      _sendStatusNow(force: true);
    }
    _reconcile();
  }

  void _markOptimistic() {
    _optimisticUntilSeq = _lastSeq;
    _optimisticDeadlineMs = nowMs() + _optimisticWindowMs;
  }

  bool _optimisticWindowActive() => _optimisticUntilSeq != null && nowMs() < _optimisticDeadlineMs;

  bool _hostIsStale() => nowMs() - _lastStateAtMs > _hostStaleTimeoutMs;

  void _reconcile() {
    if (_disposed || _settling) return;
    final state = _latestState;
    if (state == null) return;
    if (!_localReady || _optimisticWindowActive() || _hostIsStale()) return;

    switch (state.phase) {
      case PlaybackPhase.loading:
      case PlaybackPhase.waitingForPeers:
      case PlaybackPhase.paused:
        _ensurePaused();
        _alignWhileStopped(state);
      case PlaybackPhase.playing:
        _reconcilePlaying(state);
    }
  }

  void _reconcilePlaying(PlaybackState state) {
    final hostNow = clock.hostNowMs();

    if (state.anchorHostTimeMs > hostNow) {
      if (_scheduledStartSeq != state.seq) {
        _scheduledStartTimer?.cancel();
        _scheduledStartSeq = state.seq;
        final delayMs = state.anchorHostTimeMs - hostNow;
        _scheduledStartTimer = Timer(Duration(milliseconds: delayMs), () {
          _scheduledStartSeq = null;
          if (_disposed) return;
          if (_latestState?.seq != state.seq) return;
          _setPlaying();
        });
      }
      _ensurePaused();
      _alignWhileStopped(state);
      return;
    }
    if (_scheduledStartSeq != null && _scheduledStartSeq != state.seq) {
      _scheduledStartTimer?.cancel();
      _scheduledStartSeq = null;
    }

    final duration = player.duration;
    var targetMs = state.targetPositionMs(hostNow);
    if (duration > 0 && targetMs > duration) targetMs = duration;

    _setPlaying();

    final drift = player.currentPosition - targetMs;
    if (drift.abs() <= _deadbandMs) return;
    if (_cooldownElapsed()) _hardSeek(targetMs);
  }

  bool _cooldownElapsed() => nowMs() - _lastHardSeekMs >= _hardSeekCooldownMs;

  void _hardSeek(int targetMs) {
    _lastHardSeekMs = nowMs();
    _settling = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(Duration(milliseconds: _settleTimeoutMs), () {
      _settling = false;
    });
    _suppressedSeek(() => player.seekTo(targetMs < 0 ? 0 : targetMs));
  }

  void _alignWhileStopped(PlaybackState state) {
    final offBy = (player.currentPosition - state.anchorPositionMs).abs();
    if (offBy > _pausedSeekThresholdMs && _cooldownElapsed()) _hardSeek(state.anchorPositionMs);
  }

  void _ensurePaused() => _setPaused();

  void _sendStatusNow({bool force = false}) {
    final status = PeerStatus(
      ready: _localReady,
      buffering: player.playbackState == SyncPlaybackState.buffering,
      positionMs: player.currentPosition,
      rttMs: clock.minRttMs,
    );
    final last = _lastSentStatus;
    if (!force && last != null && last.ready == status.ready && last.buffering == status.buffering) return;
    _lastSentStatus = status;
    sendStatus(status);
  }
}
