import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reelay/pairing/pairing_server.dart';

void main() {
  test('serves the form page at the token path and rejects a blank URL', () async {
    final server = PairingServer(onSubmitted: (_, _) {});
    final url = await server.start();
    expect(url, isNotNull);

    try {
      final getResponse = await http.get(Uri.parse(url!));
      expect(getResponse.statusCode, 200);
      expect(getResponse.body, contains('Reelay'));
      expect(getResponse.body, contains('<form'));

      final postResponse = await http.post(
        Uri.parse('$url/submit'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'nickname=&url=',
      );
      expect(postResponse.body, contains('Paste a URL first'));
    } finally {
      await server.stop();
    }
  });

  test('submitting a nickname and url invokes onSubmitted and defaults a blank nickname', () async {
    String? gotNickname;
    String? gotUrl;
    final server = PairingServer(onSubmitted: (nickname, url) {
      gotNickname = nickname;
      gotUrl = url;
    });
    final url = await server.start();

    try {
      await http.post(
        Uri.parse('$url/submit'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'nickname=&url=${Uri.encodeQueryComponent('wss://relay.example.com?token=abc')}',
      );

      expect(gotNickname, 'My relay');
      expect(gotUrl, 'wss://relay.example.com?token=abc');
    } finally {
      await server.stop();
    }
  });

  test('a custom nickname is passed through as-is', () async {
    String? gotNickname;
    final server = PairingServer(onSubmitted: (nickname, _) => gotNickname = nickname);
    final url = await server.start();

    try {
      await http.post(
        Uri.parse('$url/submit'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'nickname=${Uri.encodeQueryComponent("Sean's relay")}&url=${Uri.encodeQueryComponent('wss://x')}',
      );

      expect(gotNickname, "Sean's relay");
    } finally {
      await server.stop();
    }
  });

  test('an unknown path returns 404', () async {
    final server = PairingServer(onSubmitted: (_, _) {});
    final url = await server.start();

    try {
      final base = Uri.parse(url!);
      final response = await http.get(base.replace(path: '/not-the-token'));
      expect(response.statusCode, 404);
    } finally {
      await server.stop();
    }
  });
}
