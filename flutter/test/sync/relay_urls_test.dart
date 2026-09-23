import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/relay_urls.dart';

void main() {
  test('wss:// maps to https:// and strips path/query into base', () {
    final url = relayHttpUrl('wss://relay.example.com:8443/socket?token=abc');
    expect(url, isNotNull);
    expect(url!.base, 'https://relay.example.com:8443');
    expect(url.query, 'token=abc');
  });

  test('ws:// maps to http://', () {
    final url = relayHttpUrl('ws://192.168.1.10:8080');
    expect(url!.base, 'http://192.168.1.10:8080');
    expect(url.query, isNull);
  });

  test('unsupported schemes return null', () {
    expect(relayHttpUrl('https://relay.example.com'), isNull);
    expect(relayHttpUrl('not-a-url'), isNull);
  });

  test('blank host returns null', () {
    expect(relayHttpUrl('wss:///socket'), isNull);
  });

  group('relayUrlToChatUrl', () {
    test('carries the relay auth query forward and appends room/name', () {
      final url = relayUrlToChatUrl('wss://relay.example.com?token=abc', 'room1', 'Sean');
      expect(url, 'https://relay.example.com/chat?token=abc&room=room1&name=Sean');
    });

    test('omits an empty default name', () {
      final url = relayUrlToChatUrl('wss://relay.example.com?token=abc', 'room1', '');
      expect(url, 'https://relay.example.com/chat?token=abc&room=room1');
    });

    test('carries the TV theme so the phone page matches it', () {
      final url = relayUrlToChatUrl('wss://relay.example.com?token=abc', 'room1', '', themeId: 'horror');
      expect(url, 'https://relay.example.com/chat?token=abc&room=room1&theme=horror');
    });

    test('returns null for an unparseable relay url', () {
      expect(relayUrlToChatUrl('not-a-url', 'room1', 'Sean'), isNull);
    });
  });
}
