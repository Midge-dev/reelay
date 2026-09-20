import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _peerIdKey = 'relay_peer_id';
const _reconnectTokenKey = 'relay_reconnect_token';
const _hostedRoomsKey = 'relay_hosted_rooms';

class HostedRoom {
  final String relayUrl;
  final String roomId;
  final String reconnectToken;

  const HostedRoom({required this.relayUrl, required this.roomId, required this.reconnectToken});

  factory HostedRoom.fromJson(Map<String, dynamic> json) => HostedRoom(
        relayUrl: json['relayUrl'] as String,
        roomId: json['roomId'] as String,
        reconnectToken: json['reconnectToken'] as String,
      );

  Map<String, dynamic> toJson() => {'relayUrl': relayUrl, 'roomId': roomId, 'reconnectToken': reconnectToken};
}

class RelayIdentity {
  final String peerId;
  final String? reconnectToken;
  final List<HostedRoom> hostedRooms;

  const RelayIdentity({required this.peerId, this.reconnectToken, this.hostedRooms = const []});
}

class RelayIdentityStore {
  final SharedPreferencesAsync _prefs;
  final Uuid _uuid = const Uuid();

  RelayIdentityStore(this._prefs);

  Future<RelayIdentity> load() async {
    var peerId = await _prefs.getString(_peerIdKey);
    if (peerId == null) {
      peerId = _uuid.v4();
      await _prefs.setString(_peerIdKey, peerId);
    }

    final hostedRoomsJson = await _prefs.getString(_hostedRoomsKey);
    final hostedRooms = _decodeHostedRooms(hostedRoomsJson);

    return RelayIdentity(
      peerId: peerId,
      reconnectToken: await _prefs.getString(_reconnectTokenKey),
      hostedRooms: hostedRooms,
    );
  }

  List<HostedRoom> _decodeHostedRooms(String? json) {
    if (json == null) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => HostedRoom.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveReconnectToken(String token) => _prefs.setString(_reconnectTokenKey, token);

  Future<void> addHostedRoom(String relayUrl, String roomId, String reconnectToken) async {
    final current = await load();
    final updated = [
      ...current.hostedRooms.where((r) => r.roomId != roomId),
      HostedRoom(relayUrl: relayUrl, roomId: roomId, reconnectToken: reconnectToken),
    ];
    await _prefs.setString(_hostedRoomsKey, jsonEncode(updated.map((r) => r.toJson()).toList()));
  }

  Future<void> removeHostedRoom(String roomId) async {
    final current = await load();
    final updated = current.hostedRooms.where((r) => r.roomId != roomId).toList();
    if (updated.isEmpty) {
      await _prefs.remove(_hostedRoomsKey);
    } else {
      await _prefs.setString(_hostedRoomsKey, jsonEncode(updated.map((r) => r.toJson()).toList()));
    }
  }
}
