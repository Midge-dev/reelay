import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'clock_sync.dart';
import 'guest_playback_reconciler.dart';
import 'host_playback_coordinator.dart';
import 'playback_state.dart';
import 'relay_client.dart';
import 'relay_protocol.dart';
import 'sync_trace.dart';
import 'synced_player.dart';
import 'time_utils.dart';

/// Wires RelayClient <-> HostPlaybackCoordinator/GuestPlaybackReconciler,
/// picking a role exactly once per session off the first non-null
/// seatIndex. The wire-format mapping functions are at the bottom of this
/// file.
class SyncViewModel {
  final SyncedPlayer player;
  final RelayClient? relay;

  /// Where this session's sync activity is recorded, if anywhere (see
  /// [SyncTrace]). The engine gets a [TracingSyncedPlayer] around [player].
  final SyncTrace? trace;

  /// This device's wall clock as clock sync reads it — tests pass one
  /// that's off, to check guests still line up with the host's clock.
  final int Function()? deviceClock;

  /// The room's guests from the stream before this one (an episode change):
  /// a new host session waits for them to load before anyone starts,
  /// rather than starting alone and making them catch up.
  final List<String> initialPeers;

  SyncViewModel({
    required SyncedPlayer player,
    required this.relay,
    this.trace,
    this.deviceClock,
    this.initialPeers = const [],
  }) : player = trace == null ? player : TracingSyncedPlayer(player, trace);

  /// The guests a host session knows of, to hand the next one.
  List<String> get knownPeers => _host?.knownPeers.toList() ?? const [];

  static const _syncKinds = {'playbackState', 'controlRequest', 'peerStatus', 'clockPing', 'clockPong', 'peerLeft'};

  Stream<ConnectionState> get connectionState =>
      relay?.connectionState ?? Stream<ConnectionState>.value(ConnectionState.disconnected);

  final _chatMessages = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get chatMessages => _chatMessages.stream;

  final _phase = BehaviorSubject<PlaybackPhase?>.seeded(null);
  Stream<PlaybackPhase?> get phase => _phase.stream;

  final _waitingOn = BehaviorSubject<List<String>>.seeded(const []);
  Stream<List<String>> get waitingOn => _waitingOn.stream;

  HostPlaybackCoordinator? _host;
  GuestPlaybackReconciler? _guest;
  ClockSync? _clock;
  StreamSubscription<RelayEvent>? _eventsSubscription;
  StreamSubscription<int?>? _roleSubscription;
  Timer? _sampleTimer;

  void start() {
    final relay = this.relay;
    if (relay == null) return;
    _eventsSubscription = relay.events.listen((event) {
      if (_syncKinds.contains(event.kind)) trace?.record('in', {'event': event.toJson()});
      _handleEvent(relay, event);
    });
    if (trace != null) _sampleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    _roleSubscription = relay.seatIndex.listen((seatIndex) {
      if (seatIndex == null || _host != null || _guest != null) return;
      if (seatIndex == 0) {
        _startAsHost(relay);
      } else {
        _startAsGuest(relay);
      }
    });
  }

  void _sample() {
    final clock = _clock;
    trace?.record('sample', {
      'pos': player.currentPosition,
      'playing': player.isPlaying,
      'state': player.playbackState.name,
      if (clock != null) 'clockOffset': clock.offsetMs,
      if (clock != null) 'rtt': clock.minRttMs,
    });
  }

  void _send(RelayClient relay, RelayEvent event) {
    trace?.record('out', {'event': event.toJson()});
    relay.send(event);
  }

  void stop() {
    _sampleTimer?.cancel();
    final traced = player;
    if (traced is TracingSyncedPlayer) traced.detach();
    _eventsSubscription?.cancel();
    _roleSubscription?.cancel();
    _host?.stop();
    _guest?.stop();
    _clock?.stop();
  }

  void dispose() {
    stop();
    _chatMessages.close();
    _phase.close();
    _waitingOn.close();
  }

  void _startAsHost(RelayClient relay) {
    trace?.record('session', {'role': 'host', 'peerId': relay.myPeerId});
    _host = HostPlaybackCoordinator(
      myPeerId: relay.myPeerId,
      player: player,
      sendState: (state) {
        _send(relay, _playbackStateToRelayEvent(state));
        _phase.add(state.phase);
        _waitingOn.add(state.waitingOn);
      },
      onWaitingOnChanged: (waitingOn) => _waitingOn.add(waitingOn),
    );
    for (final peer in initialPeers) {
      _host!.onPeerJoined(peer);
    }
    _host!.start();
  }

  void _startAsGuest(RelayClient relay) {
    trace?.record('session', {'role': 'guest', 'peerId': relay.myPeerId});
    final clockSync = ClockSync(
      nowMsFn: deviceClock,
      sendPing: (pingId) => _send(relay, RelayEvent(kind: 'clockPing', fromPeerId: relay.myPeerId, pingId: pingId)),
    );
    _clock = clockSync;
    _guest = GuestPlaybackReconciler(
      myPeerId: relay.myPeerId,
      player: player,
      clock: clockSync,
      sendControl: (request) => _send(relay, _controlRequestToRelayEvent(request, relay.myPeerId)),
      sendStatus: (status) => _send(relay, _peerStatusToRelayEvent(status, relay.myPeerId)),
    )..start();
  }

  void _handleEvent(RelayClient relay, RelayEvent event) {
    final fromPeerId = event.fromPeerId;
    if (event.kind == 'peerLeft') {
      // From the relay itself: that device's connection closed.
      if (fromPeerId != null && fromPeerId != relay.myPeerId) _host?.onPeerLeft(fromPeerId);
      return;
    }
    if (fromPeerId != null && fromPeerId != relay.myPeerId) _host?.onPeerJoined(fromPeerId);

    switch (event.kind) {
      case 'playbackState':
        final state = _relayEventToPlaybackState(event);
        if (state == null) return;
        _phase.add(state.phase);
        _waitingOn.add(state.waitingOn);
        _guest?.onState(state);
      case 'controlRequest':
        if (fromPeerId == null) return;
        final request = _relayEventToControlRequest(event);
        if (request == null) return;
        _host?.onControlRequest(fromPeerId, request);
      case 'peerStatus':
        if (fromPeerId == null) return;
        _host?.onPeerStatus(
          fromPeerId,
          PeerStatus(ready: event.ready ?? false, buffering: event.buffering ?? false, positionMs: event.positionMs ?? 0),
        );
      case 'clockPing':
        if (_host == null) return;
        if (fromPeerId == null) return;
        final pingId = event.pingId;
        if (pingId == null) return;
        _send(relay, RelayEvent(kind: 'clockPong', fromPeerId: fromPeerId, pingId: pingId, remoteTimestampMs: nowMs()));
      case 'clockPong':
        if (event.fromPeerId != relay.myPeerId) return;
        final pingId = event.pingId;
        final remoteTs = event.remoteTimestampMs;
        if (pingId == null || remoteTs == null) return;
        _clock?.onPong(pingId, remoteTs);
      case 'chat':
        _chatMessages.add(relayEventToChatMessage(event));
    }
  }
}

String _phaseToWire(PlaybackPhase phase) => switch (phase) {
      PlaybackPhase.loading => 'loading',
      PlaybackPhase.waitingForPeers => 'waitingForPeers',
      PlaybackPhase.paused => 'paused',
      PlaybackPhase.playing => 'playing',
    };

PlaybackPhase? _wireToPhase(String wire) => switch (wire) {
      'loading' => PlaybackPhase.loading,
      'waitingForPeers' => PlaybackPhase.waitingForPeers,
      'paused' => PlaybackPhase.paused,
      'playing' => PlaybackPhase.playing,
      _ => null,
    };

String _actionHintToWire(PlaybackActionHint hint) => switch (hint) {
      PlaybackActionHint.play => 'play',
      PlaybackActionHint.pause => 'pause',
      PlaybackActionHint.seek => 'seek',
    };

PlaybackActionHint? _wireToActionHint(String wire) => switch (wire) {
      'play' => PlaybackActionHint.play,
      'pause' => PlaybackActionHint.pause,
      'seek' => PlaybackActionHint.seek,
      _ => null,
    };

RelayEvent _playbackStateToRelayEvent(PlaybackState state) => RelayEvent(
      kind: 'playbackState',
      seq: state.seq,
      phase: _phaseToWire(state.phase),
      anchorPositionMs: state.anchorPositionMs,
      anchorHostTimeMs: state.anchorHostTimeMs,
      waitingOn: state.waitingOn,
      actorPeerId: state.actorPeerId,
      actionHint: state.actionHint != null ? _actionHintToWire(state.actionHint!) : null,
    );

PlaybackState? _relayEventToPlaybackState(RelayEvent event) {
  final seq = event.seq;
  final phase = event.phase != null ? _wireToPhase(event.phase!) : null;
  final anchorPositionMs = event.anchorPositionMs;
  final anchorHostTimeMs = event.anchorHostTimeMs;
  if (seq == null || phase == null || anchorPositionMs == null || anchorHostTimeMs == null) return null;
  return PlaybackState(
    seq: seq,
    phase: phase,
    anchorPositionMs: anchorPositionMs,
    anchorHostTimeMs: anchorHostTimeMs,
    waitingOn: event.waitingOn ?? const [],
    actorPeerId: event.actorPeerId,
    actionHint: event.actionHint != null ? _wireToActionHint(event.actionHint!) : null,
  );
}

RelayEvent _controlRequestToRelayEvent(ControlRequest request, String fromPeerId) => RelayEvent(
      kind: 'controlRequest',
      fromPeerId: fromPeerId,
      requestKind: switch (request.kind) {
        ControlRequestKind.play => 'play',
        ControlRequestKind.pause => 'pause',
        ControlRequestKind.seek => 'seek',
      },
      positionMs: request.positionMs,
    );

ControlRequest? _relayEventToControlRequest(RelayEvent event) {
  final kind = switch (event.requestKind) {
    'play' => ControlRequestKind.play,
    'pause' => ControlRequestKind.pause,
    'seek' => ControlRequestKind.seek,
    _ => null,
  };
  if (kind == null) return null;
  return ControlRequest(kind, positionMs: event.positionMs);
}

RelayEvent _peerStatusToRelayEvent(PeerStatus status, String fromPeerId) => RelayEvent(
      kind: 'peerStatus',
      fromPeerId: fromPeerId,
      ready: status.ready,
      buffering: status.buffering,
      positionMs: status.positionMs,
    );
