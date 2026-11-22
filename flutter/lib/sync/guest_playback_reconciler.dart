import 'dart:async';

import 'clock_sync.dart';
import 'playback_state.dart';
import 'synced_player.dart';
import 'time_utils.dart';

/// Guest-side reconciliation against the host's authoritative PlaybackState.
/// Timing constants are part of the protocol: every client must agree.
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
  // Below the host's stall grace (2500ms): a seek slower than that makes the
  // host wait for this guest where it landed, so it needs no lead.
  static const _maxSeekLeadMs = 2000;
  // While a seek is still landing, only a host target this far from it is a
  // new place to go (someone seeked); anything nearer is drift the host
  // sorts out by waiting for this guest where it lands.
  static const _inFlightRetargetMs = 10000;

  // Inside the deadband a seek costs more than it fixes (a rebuffer, on a
  // remote transcode seconds of one), so the gap is closed by playing a
  // little fast or slow instead. Start past [_nudgeStartMs] — about what
  // the clock sync and a 100ms position poll can tell apart — and stop
  // once inside [_nudgeStopMs]. Bigger gaps get the bigger step, so a
  // second closes in about ten seconds; 5-10% is too little to see and,
  // with the pitch held, hard to hear.
  static const _nudgeStartMs = 150;
  static const _nudgeStopMs = 50;
  static const _nudgeBigMs = 500;
  static const _nudgeSmallRate = 0.05;
  static const _nudgeBigRate = 0.10;

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
  int? _hardSeekStartedAtMs;

  /// Where a seek in flight is headed. A player reports buffering the
  /// moment it seeks but its old position until the seek lands, and the
  /// host decides where the room resumes from what guests report — so
  /// until this player is ready again, it reports where it's going.
  int? _seekTargetMs;
  bool _hardSeekBuffered = false;
  int _seekLeadMs = 0;
  bool _disposed = false;

  /// The rate this player was last set to (1.0 unless nudging).
  double _rate = 1.0;

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

  void _setRate(double rate) {
    if (rate == _rate) return;
    _rate = rate;
    player.setPlaybackRate(rate);
  }

  /// Plays faster (behind the host) or slower (ahead) until within
  /// [_nudgeStopMs]; real time otherwise.
  void _nudge(int driftMs) {
    final off = driftMs.abs();
    final nudging = _rate != 1.0;
    if (off <= _nudgeStopMs || (!nudging && off < _nudgeStartMs)) {
      _setRate(1.0);
      return;
    }
    final step = off >= _nudgeBigMs ? _nudgeBigRate : _nudgeSmallRate;
    _setRate(driftMs > 0 ? 1.0 - step : 1.0 + step);
  }

  void _setPaused() {
    _setRate(1.0);
    if (player.isPlaying) {
      _expectPlayWhenReady(false);
      player.pause();
    }
  }

  /// Whether this guest has played in the room yet. Until it has, it is
  /// arriving: when the room holds for it, it goes to the room's spot.
  bool _hasPlayedInRoom = false;

  void _setPlaying() {
    _hasPlayedInRoom = true;
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
      if (state == SyncPlaybackState.buffering && _hardSeekStartedAtMs != null) _hardSeekBuffered = true;
      if (state == SyncPlaybackState.ready && _hardSeekBuffered) _measureSeekLead();
      if (state == SyncPlaybackState.ready) _seekTargetMs = null;
      _sendStatusNow();
    },
    onSeek: (positionMs) {
      _seekTargetMs = positionMs;
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
    _setRate(1.0);
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
      case PlaybackPhase.waitingForPeers when state.waitingOn.contains(myPeerId) && _hasPlayedInRoom:
        // The room waits for this guest where it is (the host moves to it),
        // so seeking now would only move the spot it's waiting at. (A guest
        // that hasn't played yet is arriving, and goes to the room's spot.)
        _ensurePaused();
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

    if (_seekLanding(targetMs)) return;
    if (player.playbackState == SyncPlaybackState.buffering) {
      _setRate(1.0);
      return;
    }
    final drift = player.currentPosition - targetMs;
    if (drift.abs() <= _deadbandMs) {
      _nudge(drift);
      return;
    }
    _setRate(1.0);
    if (!_cooldownElapsed()) return;
    var leadTargetMs = targetMs + _seekLeadMs;
    if (duration > 0 && leadTargetMs > duration) leadTargetMs = duration;
    _hardSeek(leadTargetMs);
  }

  /// A seek while the room plays lands where the host *was*: the host plays
  /// on while this player rebuffers, so a guest whose seeks take longer than
  /// the deadband lands out of sync, seeks again, and never catches up. Aim
  /// ahead by how long the last seek took to come back.
  void _measureSeekLead() {
    final startedAt = _hardSeekStartedAtMs;
    if (startedAt == null) return;
    _hardSeekStartedAtMs = null;
    _hardSeekBuffered = false;
    final tookMs = nowMs() - startedAt;
    _seekLeadMs = tookMs > _maxSeekLeadMs ? _maxSeekLeadMs : tookMs;
  }

  bool _cooldownElapsed() => nowMs() - _lastHardSeekMs >= _hardSeekCooldownMs;

  void _hardSeek(int targetMs) {
    _lastHardSeekMs = nowMs();
    _hardSeekStartedAtMs = _lastHardSeekMs;
    _hardSeekBuffered = false;
    _settling = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(Duration(milliseconds: _settleTimeoutMs), () {
      _settling = false;
      // Never rebuffered: the seek was as good as instant.
      if (_hardSeekStartedAtMs != null && !_hardSeekBuffered) {
        _hardSeekStartedAtMs = null;
        _seekLeadMs = 0;
      }
    });
    _suppressedSeek(() => player.seekTo(targetMs < 0 ? 0 : targetMs));
    // Already buffering from an earlier seek, the player reports no change —
    // but the host needs to know where this one is headed.
    _sendStatusNow(force: true);
  }

  /// A seek is still buffering and [targetMs] is near where it's headed:
  /// let it land rather than restart it.
  bool _seekLanding(int targetMs) {
    final inFlight = _seekTargetMs;
    if (inFlight == null || player.playbackState != SyncPlaybackState.buffering) return false;
    return (targetMs - inFlight).abs() < _inFlightRetargetMs;
  }

  void _alignWhileStopped(PlaybackState state) {
    if (_seekLanding(state.anchorPositionMs)) return;
    final offBy = (player.currentPosition - state.anchorPositionMs).abs();
    // Paused, the room is a still frame to match. Waiting to resume, a gap
    // under the deadband is closed by speed once it plays — a seek here
    // costs a rebuffer the room then waits for, and the host may be moving
    // to this guest meanwhile (fuzz seed 1968).
    final thresholdMs = state.phase == PlaybackPhase.paused ? _pausedSeekThresholdMs : _deadbandMs;
    if (offBy > thresholdMs && _cooldownElapsed()) _hardSeek(state.anchorPositionMs);
  }

  void _ensurePaused() => _setPaused();

  void _sendStatusNow({bool force = false}) {
    final buffering = player.playbackState == SyncPlaybackState.buffering;
    final status = PeerStatus(
      ready: _localReady,
      buffering: buffering,
      positionMs: (buffering ? _seekTargetMs : null) ?? player.currentPosition,
      rttMs: clock.minRttMs,
    );
    final last = _lastSentStatus;
    if (!force && last != null && last.ready == status.ready && last.buffering == status.buffering) return;
    _lastSentStatus = status;
    sendStatus(status);
  }
}
