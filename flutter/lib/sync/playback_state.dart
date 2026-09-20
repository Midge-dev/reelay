enum PlaybackPhase { loading, waitingForPeers, paused, playing }

enum PlaybackActionHint { play, pause, seek }

class PlaybackState {
  final int seq;
  final PlaybackPhase phase;
  final int anchorPositionMs;
  final int anchorHostTimeMs;
  final List<String> waitingOn;
  final String? actorPeerId;
  final PlaybackActionHint? actionHint;

  const PlaybackState({
    required this.seq,
    required this.phase,
    required this.anchorPositionMs,
    required this.anchorHostTimeMs,
    this.waitingOn = const [],
    this.actorPeerId,
    this.actionHint,
  });

  int targetPositionMs(int hostNowMs) {
    if (phase == PlaybackPhase.playing) {
      final target = anchorPositionMs + (hostNowMs - anchorHostTimeMs);
      return target < 0 ? 0 : target;
    }
    return anchorPositionMs;
  }
}

class PeerStatus {
  final bool ready;
  final bool buffering;
  final int positionMs;
  final int? rttMs;

  const PeerStatus({required this.ready, required this.buffering, required this.positionMs, this.rttMs});
}

enum ControlRequestKind { play, pause, seek }

class ControlRequest {
  final ControlRequestKind kind;
  final int? positionMs;

  const ControlRequest(this.kind, {this.positionMs});
}
