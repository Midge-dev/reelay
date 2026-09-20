import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/relay_protocol.dart';

void main() {
  test('RelayEvent round-trips through JSON preserving the wire field names', () {
    const event = RelayEvent(
      kind: 'playbackState',
      seq: 7,
      phase: 'playing',
      anchorPositionMs: 12345,
      anchorHostTimeMs: 67890,
      waitingOn: ['peer-a', 'peer-b'],
      actorPeerId: 'peer-a',
      actionHint: 'seek',
    );

    final decoded = RelayEvent.fromJson(event.toJson());

    expect(decoded.kind, 'playbackState');
    expect(decoded.seq, 7);
    expect(decoded.phase, 'playing');
    expect(decoded.anchorPositionMs, 12345);
    expect(decoded.anchorHostTimeMs, 67890);
    expect(decoded.waitingOn, ['peer-a', 'peer-b']);
    expect(decoded.actorPeerId, 'peer-a');
    expect(decoded.actionHint, 'seek');
  });

  test('toJson omits null fields rather than writing explicit nulls', () {
    const event = RelayEvent(kind: 'chat', text: 'hi');

    final json = event.toJson();

    expect(json.containsKey('seq'), isFalse);
    expect(json.containsKey('fromPeerId'), isFalse);
    expect(json['kind'], 'chat');
    expect(json['text'], 'hi');
  });

  test('relayEventToChatMessage defaults username to "them" and text to empty', () {
    const event = RelayEvent(kind: 'chat');

    final message = relayEventToChatMessage(event);

    expect(message.username, 'them');
    expect(message.text, '');
  });
}
