import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/settings/relay_identity_store.dart';
import 'relay_protocol.dart';

const _initialBackoffMs = 1000;
const _maxBackoffMs = 30000;

sealed class RoomIntent {
  const RoomIntent();
}

class CreateRoom extends RoomIntent {
  final String title;
  final String? thumb;
  final String? ratingKey;
  final String hostName;
  final int? maxSeats;

  const CreateRoom({required this.title, this.thumb, this.ratingKey, required this.hostName, this.maxSeats});
}

class JoinRoom extends RoomIntent {
  final String roomId;

  const JoinRoom(this.roomId);
}

/// One WebSocket per client to a relay server, host-authoritative room
/// model (seatIndex == 0 is always host): reconnect
/// with exponential backoff (1s -> 30s doubling), a connection-generation
/// counter so a stale attempt's cleanup can never clobber state set by a
/// newer one, and the same `{type, payload}` event envelope on the wire.
class RelayClient {
  final String relayUrl;
  final void Function(RelayIdentity) onIdentityUpdated;
  final void Function(String roomId, String reconnectToken) onHostedRoomIdUpdated;

  RelayClient(
    this.relayUrl,
    RelayIdentity identity, {
    this.onIdentityUpdated = _noopIdentity,
    this.onHostedRoomIdUpdated = _noopHostedRoom,
  }) : _identity = identity;

  static void _noopIdentity(RelayIdentity _) {}
  static void _noopHostedRoom(String roomId, String reconnectToken) {}

  RelayIdentity _identity;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _connectionGeneration = 0;
  Timer? _reconnectTimer;
  int _backoffMs = _initialBackoffMs;
  bool _manuallyDisconnected = false;
  ConnectionState? _lastRejection;
  RoomIntent? _intent;

  final _eventsController = StreamController<RelayEvent>.broadcast();
  Stream<RelayEvent> get events => _eventsController.stream;

  final _connectionState = BehaviorSubject<ConnectionState>.seeded(ConnectionState.disconnected);
  Stream<ConnectionState> get connectionState => _connectionState.stream;
  ConnectionState get connectionStateValue => _connectionState.value;

  final _seatIndex = BehaviorSubject<int?>.seeded(null);
  Stream<int?> get seatIndex => _seatIndex.stream;
  int? get seatIndexValue => _seatIndex.value;

  final _roomId = BehaviorSubject<String?>.seeded(null);
  Stream<String?> get roomId => _roomId.stream;
  String? get roomIdValue => _roomId.value;

  String get myPeerId => _identity.peerId;

  void connect(RoomIntent intent) {
    _intent = intent;
    _manuallyDisconnected = false;
    _backoffMs = _initialBackoffMs;
    _attemptConnect();
  }

  Future<void> _attemptConnect() async {
    final intent = _intent;
    if (intent == null) return;
    _lastRejection = null;
    _connectionState.add(ConnectionState.connecting);
    final myGeneration = ++_connectionGeneration;

    var finished = false;
    void finishAndMaybeReconnect() {
      if (finished) return;
      finished = true;
      if (myGeneration == _connectionGeneration) {
        _channel = null;
        _seatIndex.add(null);
        _scheduleReconnect();
      }
    }

    WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      await channel.ready;
    } catch (_) {
      finishAndMaybeReconnect();
      return;
    }

    _channel = channel;
    _backoffMs = _initialBackoffMs;

    final request = <String, dynamic>{
      ...switch (intent) {
        CreateRoom() => {
            'type': 'createRoom',
            'title': intent.title,
            if (intent.thumb != null) 'thumb': intent.thumb,
            if (intent.ratingKey != null) 'ratingKey': intent.ratingKey,
            'hostName': intent.hostName,
            if (intent.maxSeats != null) 'maxSeats': intent.maxSeats,
          },
        JoinRoom() => {'type': 'joinRoom', 'roomId': intent.roomId},
      },
      'peerId': _identity.peerId,
      if (_identity.reconnectToken != null) 'reconnectToken': _identity.reconnectToken,
    };
    channel.sink.add(jsonEncode(request));

    _subscription = channel.stream.listen(
      (data) {
        if (data is String) _handleFrame(data);
      },
      onError: (_) => finishAndMaybeReconnect(),
      onDone: finishAndMaybeReconnect,
    );
  }

  void _handleFrame(String text) {
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (root['type'] as String?) {
      case 'welcome':
        final newToken = root['reconnectToken'] as String?;
        if (newToken != null && newToken != _identity.reconnectToken) {
          _identity = RelayIdentity(peerId: _identity.peerId, reconnectToken: newToken, hostedRooms: _identity.hostedRooms);
          onIdentityUpdated(_identity);
        }
        final seat = root['seatIndex'] as int?;
        _seatIndex.add(seat);
        final newRoomId = root['roomId'] as String?;
        if (newRoomId != null) _roomId.add(newRoomId);
        if (seat == 0 && newRoomId != null && _identity.reconnectToken != null) {
          onHostedRoomIdUpdated(newRoomId, _identity.reconnectToken!);
        }
        _connectionState.add(ConnectionState.connected);
      case 'full':
        _lastRejection = ConnectionState.roomFull;
        _connectionState.add(ConnectionState.roomFull);
      case 'notFound':
        _lastRejection = ConnectionState.roomNotFound;
        _connectionState.add(ConnectionState.roomNotFound);
      case 'closed':
        _manuallyDisconnected = true;
        _connectionState.add(ConnectionState.roomClosed);
      case 'event':
        final payload = root['payload'];
        if (payload == null) return;
        try {
          _eventsController.add(RelayEvent.fromJson(payload as Map<String, dynamic>));
        } catch (_) {}
    }
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected) return;
    _connectionState.add(_lastRejection ?? ConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () {
      _backoffMs = (_backoffMs * 2).clamp(_initialBackoffMs, _maxBackoffMs);
      if (!_manuallyDisconnected) _attemptConnect();
    });
  }

  void retryNow() {
    if (_manuallyDisconnected) return;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _backoffMs = _initialBackoffMs;
    _attemptConnect();
  }

  void send(RelayEvent event) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': 'event', 'payload': event.toJson()}));
    } catch (_) {}
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _intent = null;
    _seatIndex.add(null);
    _roomId.add(null);
    _connectionState.add(ConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _connectionState.close();
    _seatIndex.close();
    _roomId.close();
  }
}
