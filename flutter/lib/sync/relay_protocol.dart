import 'time_utils.dart';

enum ConnectionState { disconnected, connecting, connected, reconnecting, roomFull, roomNotFound, roomClosed }

class RelayRoomSummary {
  final String roomId;
  final String title;
  final String? thumb;
  final String? ratingKey;
  final String hostName;
  final int occupants;
  final int maxSeats;

  const RelayRoomSummary({
    required this.roomId,
    required this.title,
    this.thumb,
    this.ratingKey,
    required this.hostName,
    required this.occupants,
    required this.maxSeats,
  });

  factory RelayRoomSummary.fromJson(Map<String, dynamic> json) => RelayRoomSummary(
        roomId: json['roomId'] as String,
        title: json['title'] as String,
        thumb: json['thumb'] as String?,
        ratingKey: json['ratingKey'] as String?,
        hostName: json['hostName'] as String,
        occupants: json['occupants'] as int,
        maxSeats: json['maxSeats'] as int,
      );
}

/// The fixed wire contract for every app-level relay message — a flat
/// struct carrying every possible field as nullable, discriminated by
/// [kind]. Deliberately "kitchen sink"-shaped to match RelayProtocol.kt
/// exactly; preserve this shape for wire compatibility with any other
/// client (Kotlin or otherwise) talking to the same relay server.
class RelayEvent {
  final String kind;
  final String? username;
  final String? avatarUrl;
  final String? fromPeerId;
  final int? seq;
  final String? phase;
  final int? anchorPositionMs;
  final int? anchorHostTimeMs;
  final double? rate;
  final List<String>? waitingOn;
  final String? actorPeerId;
  final String? actionHint;
  final String? requestKind;
  final int? positionMs;
  final bool? ready;
  final bool? buffering;
  final int? pingId;
  final int? remoteTimestampMs;
  final String? text;

  const RelayEvent({
    required this.kind,
    this.username,
    this.avatarUrl,
    this.fromPeerId,
    this.seq,
    this.phase,
    this.anchorPositionMs,
    this.anchorHostTimeMs,
    this.rate,
    this.waitingOn,
    this.actorPeerId,
    this.actionHint,
    this.requestKind,
    this.positionMs,
    this.ready,
    this.buffering,
    this.pingId,
    this.remoteTimestampMs,
    this.text,
  });

  factory RelayEvent.fromJson(Map<String, dynamic> json) => RelayEvent(
        kind: json['kind'] as String,
        username: json['username'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        fromPeerId: json['fromPeerId'] as String?,
        seq: json['seq'] as int?,
        phase: json['phase'] as String?,
        anchorPositionMs: json['anchorPositionMs'] as int?,
        anchorHostTimeMs: json['anchorHostTimeMs'] as int?,
        rate: (json['rate'] as num?)?.toDouble(),
        waitingOn: (json['waitingOn'] as List<dynamic>?)?.map((e) => e as String).toList(),
        actorPeerId: json['actorPeerId'] as String?,
        actionHint: json['actionHint'] as String?,
        requestKind: json['requestKind'] as String?,
        positionMs: json['positionMs'] as int?,
        ready: json['ready'] as bool?,
        buffering: json['buffering'] as bool?,
        pingId: json['pingId'] as int?,
        remoteTimestampMs: json['remoteTimestampMs'] as int?,
        text: json['text'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (fromPeerId != null) 'fromPeerId': fromPeerId,
        if (seq != null) 'seq': seq,
        if (phase != null) 'phase': phase,
        if (anchorPositionMs != null) 'anchorPositionMs': anchorPositionMs,
        if (anchorHostTimeMs != null) 'anchorHostTimeMs': anchorHostTimeMs,
        if (rate != null) 'rate': rate,
        if (waitingOn != null) 'waitingOn': waitingOn,
        if (actorPeerId != null) 'actorPeerId': actorPeerId,
        if (actionHint != null) 'actionHint': actionHint,
        if (requestKind != null) 'requestKind': requestKind,
        if (positionMs != null) 'positionMs': positionMs,
        if (ready != null) 'ready': ready,
        if (buffering != null) 'buffering': buffering,
        if (pingId != null) 'pingId': pingId,
        if (remoteTimestampMs != null) 'remoteTimestampMs': remoteTimestampMs,
        if (text != null) 'text': text,
      };
}

class ChatMessage {
  final String username;
  final String text;
  final int receivedAtMs;

  const ChatMessage({required this.username, required this.text, required this.receivedAtMs});
}

ChatMessage relayEventToChatMessage(RelayEvent event) => ChatMessage(
      username: event.username ?? 'them',
      text: event.text ?? '',
      receivedAtMs: nowMs(),
    );
