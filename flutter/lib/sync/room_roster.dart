import 'dart:async';

import 'relay_client.dart';
import 'relay_protocol.dart';

/// Someone else in the room, as their own presence last described them.
class RoomPerson {
  final String peerId;
  final String name;
  final String? avatarUrl;
  final int lastSeenMs;

  const RoomPerson(this.peerId, this.name, this.avatarUrl, this.lastSeenMs);
}

/// Who is in a Watch Together room during playback (screen 15), from the
/// same `presence` events the lobby uses: each client says who it is every
/// few seconds, and anyone not heard from in three rounds has gone. The
/// sync layer only knows peer ids ("waiting on a1b2…"); this is what turns
/// them into "Marcus is buffering".
class RoomRoster {
  static const presenceInterval = Duration(seconds: 3);
  static const _staleAfter = Duration(seconds: 9);

  final RelayClient relay;
  final String localName;
  final String? localAvatarUrl;
  final int Function() _now;

  RoomRoster({
    required this.relay,
    required this.localName,
    this.localAvatarUrl,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final _people = <String, RoomPerson>{};
  final _changes = StreamController<List<RoomPerson>>.broadcast();
  StreamSubscription<RelayEvent>? _sub;
  Timer? _timer;

  /// Everyone else, oldest arrival first.
  Stream<List<RoomPerson>> get people => _changes.stream;
  List<RoomPerson> get current => _people.values.toList();

  String? nameOf(String peerId) => _people[peerId]?.name;

  void start() {
    _sub = relay.events.listen(handle);
    _announce();
    _timer = Timer.periodic(presenceInterval, (_) {
      _announce();
      _prune();
    });
  }

  void _announce() => relay.send(
    RelayEvent(
      kind: 'presence',
      fromPeerId: relay.myPeerId,
      username: localName,
      avatarUrl: localAvatarUrl,
    ),
  );

  /// Public for tests; [start] wires it to the relay.
  void handle(RelayEvent event) {
    if (event.kind != 'presence') return;
    final from = event.fromPeerId;
    if (from == null || from == relay.myPeerId) return;
    _people[from] = RoomPerson(
      from,
      event.username ?? 'Guest',
      event.avatarUrl,
      _now(),
    );
    _changes.add(current);
  }

  void _prune() {
    final cutoff = _now() - _staleAfter.inMilliseconds;
    final before = _people.length;
    _people.removeWhere((_, p) => p.lastSeenMs < cutoff);
    if (_people.length != before) _changes.add(current);
  }

  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _changes.close();
  }
}

/// "Marcus", "Marcus and Sam", "3 people" — who the room is waiting on.
/// Unknown peers (presence not heard yet) count but aren't named.
String waitingOnPhrase(List<String> peerIds, String? Function(String) nameOf) {
  final names = [for (final id in peerIds) ?nameOf(id)];
  if (names.length != peerIds.length || peerIds.length > 2) {
    return peerIds.length == 1 ? 'Someone' : '${peerIds.length} people';
  }
  return names.join(' and ');
}
