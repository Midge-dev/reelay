import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:reelay/sync/relay_client.dart';
import 'package:reelay/sync/relay_protocol.dart';
import 'package:rxdart/rxdart.dart';

/// One device's link to the relay: a base one-way delay plus jitter, in
/// each direction. Messages on one link stay in order (it's one WebSocket
/// over TCP) — jitter only ever delays, never reorders.
class LinkProfile {
  final int upMs;
  final int downMs;
  final int jitterMs;

  const LinkProfile({this.upMs = 40, this.downMs = 40, this.jitterMs = 0});

  static const lan = LinkProfile(upMs: 15, downMs: 15, jitterMs: 5);
  static const home = LinkProfile(upMs: 45, downMs: 45, jitterMs: 25);

  /// Across the country to a free Render relay that's slow to answer.
  static const far = LinkProfile(upMs: 160, downMs: 120, jitterMs: 120);

  @override
  String toString() => 'up ${upMs}ms, down ${downMs}ms, jitter ±${jitterMs}ms';
}

class _Lane {
  int _lastDeliveryMs = 0;

  void send(int nowMs, int delayMs, void Function() deliver) {
    final at = max(nowMs + delayMs, _lastDeliveryMs);
    _lastDeliveryMs = at;
    Timer(Duration(milliseconds: at - nowMs), deliver);
  }
}

/// The relay server's job, as `relay/server.js` does it: seat 0 hosts, and
/// an `event` from one seat goes to every other seat, unchanged.
class SimRelayServer {
  SimRelayServer({required this.random, required this.now});

  final Random random;
  final int Function() now;
  final List<SimRelayClient?> _seats = [];

  SimRelayClient connect(String peerId, LinkProfile link) {
    final client = SimRelayClient._(this, peerId, link, _seats.length);
    _seats.add(client);
    return client;
  }

  int _delay(int baseMs, int jitterMs) => baseMs + (jitterMs > 0 ? random.nextInt(jitterMs + 1) : 0);

  void _fromClient(SimRelayClient sender, String frame) {
    sender._up.send(now(), _delay(sender.link.upMs, sender.link.jitterMs), () {
      if (!sender._connected) return;
      final payload = (jsonDecode(frame) as Map<String, dynamic>)['payload'] as Map<String, dynamic>;
      final out = jsonEncode({'type': 'event', 'payload': payload});
      for (final seat in _seats) {
        if (seat == null || identical(seat, sender) || !seat._connected) continue;
        seat._down.send(now(), _delay(seat.link.downMs, seat.link.jitterMs), () => seat._deliver(out));
      }
    });
  }

  /// Like server.js's releaseConnection: the seat empties and everyone
  /// still there hears `peerLeft`.
  void _leave(SimRelayClient client) {
    final i = _seats.indexOf(client);
    if (i < 0) return;
    _seats[i] = null;
    final out = jsonEncode({'type': 'event', 'payload': {'kind': 'peerLeft', 'fromPeerId': client.myPeerId}});
    for (final seat in _seats) {
      if (seat == null || !seat._connected) continue;
      seat._down.send(now(), _delay(seat.link.downMs, seat.link.jitterMs), () => seat._deliver(out));
    }
  }
}

/// A [RelayClient] whose WebSocket is the [SimRelayServer]: everything
/// sent goes through the real JSON wire format, so the simulation also
/// exercises [RelayEvent]'s encoding.
class SimRelayClient implements RelayClient {
  SimRelayClient._(this._server, this._peerId, this.link, int seat) {
    _seat.add(seat);
    _state.add(ConnectionState.connected);
  }

  final SimRelayServer _server;
  final String _peerId;
  final LinkProfile link;
  final _up = _Lane();
  final _down = _Lane();
  bool _connected = true;

  final _events = StreamController<RelayEvent>.broadcast(sync: true);
  final _seat = BehaviorSubject<int?>();
  final _state = BehaviorSubject<ConnectionState>();

  void _deliver(String frame) {
    if (!_connected) return;
    final root = jsonDecode(frame) as Map<String, dynamic>;
    _events.add(RelayEvent.fromJson(root['payload'] as Map<String, dynamic>));
  }

  /// The device goes away without a word — app closed, Wi-Fi gone.
  void drop() {
    _connected = false;
    _server._leave(this);
  }

  @override
  String get myPeerId => _peerId;
  @override
  Stream<RelayEvent> get events => _events.stream;
  @override
  Stream<int?> get seatIndex => _seat.stream;
  @override
  int? get seatIndexValue => _seat.value;
  @override
  Stream<ConnectionState> get connectionState => _state.stream;
  @override
  ConnectionState get connectionStateValue => _state.value;

  @override
  void send(RelayEvent event) {
    if (!_connected) return;
    _server._fromClient(this, jsonEncode({'type': 'event', 'payload': event.toJson()}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('SimRelayClient: ${invocation.memberName}');
}
