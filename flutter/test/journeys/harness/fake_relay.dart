import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/sync/relay_client.dart';
import 'package:reelay/sync/playback_state.dart';
import 'package:reelay/sync/relay_protocol.dart';
import 'package:reelay/sync/room_roster.dart';
import 'package:reelay/sync/sync_view_model.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../sync/sim/sim_player.dart';
import 'fake_http.dart';

/// A Watch Together relay in the test process, behaving as
/// `relay/server.js` does: seat 0 hosts, an `event` from one seat goes to
/// every other seat unchanged, a dropped seat makes everyone else hear
/// `peerLeft`, `/rooms` lists rooms whose host is connected, and the host's
/// `/rooms/:id/close` sends everyone `closed`.
///
/// The app reaches it through [RelayClient.openChannel] (sockets) and
/// [route] (the HTTP directory); a [Friend] is the other device in the room.
class FakeRelay {
  FakeRelay({this.url = 'wss://relay.test'});

  final String url;
  final rooms = <String, FakeRoom>{};
  var _nextRoom = 1;

  /// Every event any seat sent, in order, as `kind from peer`.
  final eventLog = <RelayEvent>[];

  WebSocketChannel open(Uri uri) => _Socket(this);

  FakeReply? route(FakeRequest r) {
    if (r.uri.host != Uri.parse(url).host) return null;
    if (r.method == 'GET' && r.uri.path == '/rooms') {
      return FakeReply.json([
        for (final room in rooms.values)
          if (room.seats.isNotEmpty && room.seats.first != null) room.summary(),
      ]);
    }
    final closeRoom = RegExp(r'^/rooms/([^/]+)/close$').firstMatch(r.uri.path);
    if (r.method == 'POST' && closeRoom != null) {
      return close(closeRoom[1]!) ? FakeReply.json({'ok': true}) : FakeReply.json({'ok': false}, status: 404);
    }
    return FakeReply.bytes(utf8.encode('reelay relay ok\n'), contentType: 'text/plain');
  }

  /// Ends [roomId] for everyone in it, as the host's close request does.
  bool close(String roomId) {
    final room = rooms.remove(roomId);
    if (room == null) return false;
    for (final seat in room.seats.whereType<_Socket>()) {
      seat._toClient({'type': 'closed'});
      seat._hangUp();
    }
    return true;
  }

  void _fromClient(_Socket from, Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'createRoom':
        final room = FakeRoom('room${_nextRoom++}', msg);
        rooms[room.id] = room;
        _seat(from, room, msg['peerId'] as String);
      case 'joinRoom':
        final room = rooms[msg['roomId']];
        if (room == null) {
          from._toClient({'type': 'notFound'});
          from._hangUp();
          return;
        }
        _seat(from, room, msg['peerId'] as String);
      case 'event':
        final payload = msg['payload'] as Map<String, dynamic>;
        eventLog.add(RelayEvent.fromJson(payload));
        final room = from.room;
        if (room == null) return;
        if (payload['kind'] == 'episodeSwitch' && room.seats.first == from) {
          room.info['title'] = payload['title'] ?? room.info['title'];
          room.info['ratingKey'] = payload['ratingKey'] ?? room.info['ratingKey'];
          room.info['ids'] = payload['ids'] ?? const [];
        }
        for (final seat in room.seats) {
          if (seat != null && seat != from) seat._toClient({'type': 'event', 'payload': payload});
        }
    }
  }

  void _seat(_Socket socket, FakeRoom room, String peerId) {
    var index = room.peerIds.indexOf(peerId);
    if (index < 0) {
      index = room.seats.indexOf(null);
      if (index < 0) {
        room.seats.add(null);
        room.peerIds.add(peerId);
        index = room.seats.length - 1;
      } else {
        room.peerIds[index] = peerId;
      }
    }
    room.seats[index] = socket;
    socket.room = room;
    socket.peerId = peerId;
    socket._toClient({'type': 'welcome', 'roomId': room.id, 'peerId': peerId, 'reconnectToken': 'tok-$peerId', 'seatIndex': index});
  }

  void _gone(_Socket socket) {
    final room = socket.room;
    if (room == null) return;
    final i = room.seats.indexOf(socket);
    if (i < 0) return;
    room.seats[i] = null;
    for (final seat in room.seats) {
      seat?._toClient({
        'type': 'event',
        'payload': {'kind': 'peerLeft', 'fromPeerId': socket.peerId},
      });
    }
  }

  /// The room hosted by [hostName], if one is open.
  FakeRoom? roomOf(String hostName) {
    for (final room in rooms.values) {
      if (room.info['hostName'] == hostName) return room;
    }
    return null;
  }
}

class FakeRoom {
  FakeRoom(this.id, Map<String, dynamic> create) : info = Map.of(create);

  final String id;
  final Map<String, dynamic> info;
  final seats = <_Socket?>[];
  final peerIds = <String>[];

  int get occupants => seats.whereType<_Socket>().length;

  Map<String, Object?> summary() => {
    'roomId': id,
    'title': info['title'] ?? 'Untitled',
    'thumb': info['thumb'],
    'ratingKey': info['ratingKey'],
    'serverId': info['serverId'],
    'ids': info['ids'] ?? const [],
    'mediaTitle': info['mediaTitle'],
    'year': info['year'],
    'hostName': info['hostName'] ?? 'Host',
    'occupants': occupants,
    'maxSeats': info['maxSeats'] ?? 8,
  };
}

/// One open socket: what the client writes goes to the relay, what the
/// relay says arrives on [stream] a moment later (never synchronously, like
/// a real socket).
class _Socket implements WebSocketChannel {
  _Socket(this._relay) {
    sink = _Sink(this);
  }

  final FakeRelay _relay;
  final _incoming = StreamController<dynamic>();
  FakeRoom? room;
  String? peerId;
  bool _open = true;

  void _toClient(Map<String, Object?> frame) {
    if (!_open) return;
    final text = jsonEncode(frame);
    scheduleMicrotask(() {
      if (!_incoming.isClosed) _incoming.add(text);
    });
  }

  /// The relay ends the connection.
  void _hangUp() {
    if (!_open) return;
    _open = false;
    scheduleMicrotask(_incoming.close);
  }

  void _clientClosed() {
    if (!_open) return;
    _open = false;
    _relay._gone(this);
    _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  late final WebSocketSink sink;
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('fake socket: ${invocation.memberName}');
}

class _Sink implements WebSocketSink {
  _Sink(this._socket);
  final _Socket _socket;

  @override
  void add(dynamic data) {
    if (!_socket._open) return;
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    scheduleMicrotask(() => _socket._relay._fromClient(_socket, msg));
  }

  @override
  Future close([int? closeCode, String? closeReason]) async => _socket._clientClosed();

  @override
  Future get done => _socket._incoming.done;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => stream.forEach(add);
}

/// The other device in the room — a friend on their own TV, with the app's
/// real relay client, sync logic and presence on a simulated player that
/// plays on in time. Host a room for the app to join, or join the app's.
///
/// It says what a real device says when: a host in the lobby announces
/// nothing (the app's lobby doesn't), a guest in the lobby announces itself,
/// and everyone announces themselves once playing (RoomRoster).
class Friend {
  Friend(this.relay, {this.name = 'Riley', String peerId = 'friend-peer'})
    : client = RelayClient(relay.url, RelayIdentity(peerId: peerId));

  final FakeRelay relay;
  final String name;
  final RelayClient client;
  SimPlayer? _player;
  SyncViewModel? sync;
  RoomRoster? _roster;
  StreamSubscription<RelayEvent>? _events;
  bool _hosting = false;

  /// The room's phase as this friend's own sync sees it (a host doesn't
  /// hear its own states, so [roomPhase] is a guest's view).
  PlaybackPhase? phase;
  StreamSubscription<PlaybackPhase?>? _phaseSub;
  bool _left = false;

  /// The friend's player, once it has started.
  SimPlayer get player => _player ?? (throw StateError('$name has not started playing'));
  bool get playing => _player?.isPlaying ?? false;

  /// Every event this friend has heard from the room.
  final heard = <RelayEvent>[];

  /// The room's latest playback phase, as this friend last heard it.
  String? get roomPhase => heard.lastWhere((e) => e.kind == 'playbackState', orElse: () => const RelayEvent(kind: '')).phase;

  void _listen() {
    _events = client.events.listen((e) {
      heard.add(e);
      // The lobby's Start for everyone, from the app: the friend's player
      // opens and plays, as LobbyScreen's onStart does.
      if (e.kind == 'start' && _player == null) play();
    });
  }

  void _announce() => _roster ??= (RoomRoster(relay: client, localName: name)..start());

  /// Opens a room for [title] — on the friend's own server, found by the
  /// app through [ids] — and waits in the lobby until [start].
  void host({required String title, required List<String> ids, int? year}) {
    _hosting = true;
    client.connect(CreateRoom(title: title, hostName: name, ratingKey: 'their-$title', serverId: 'friends-server', ids: ids, mediaTitle: title, year: year));
    _listen();
  }

  /// Joins the room [roomId] as a guest, and waits in its lobby.
  void join(String roomId) {
    client.connect(JoinRoom(roomId));
    _listen();
    _announce();
  }

  /// Presses Start for everyone in the lobby.
  void start({int atMs = 0}) {
    client.send(RelayEvent(kind: 'start', fromPeerId: client.myPeerId, username: name));
    play(atMs: atMs);
  }

  /// The friend's player opens and plays (after either side's Start).
  void play({int atMs = 0}) {
    final player = _player ??= SimPlayer(PlayerProfile.directPlay, random: Random(7), startMs: atMs);
    if (sync == null) {
      sync = SyncViewModel(player: player, relay: client)..start();
      _phaseSub = sync!.phase.listen((p) => phase = p);
    }
    _announce();
    player.play();
  }

  /// The friend presses pause or play on their remote.
  void pressPause() => player.pause();
  void pressPlay() => player.play();

  /// The host ends the room for everyone (End session).
  void endRoom() {
    assert(_hosting, 'only the host can end the room');
    final id = client.roomIdValue;
    if (id != null) relay.close(id);
  }

  /// The friend's app goes away (Back out of the room, or the TV off).
  void leave() {
    if (_left) return;
    _left = true;
    sync?.stop();
    _phaseSub?.cancel();
    _roster?.dispose();
    _events?.cancel();
    _player?.dispose();
    client.dispose();
  }
}
