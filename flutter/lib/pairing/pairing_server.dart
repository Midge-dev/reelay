import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _pairingPageCss = '''
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      background: #0D0D12; color: #F2F2F5; font-family: -apple-system, system-ui, sans-serif;
      padding: 24px;
    }
    .card {
      width: 100%; max-width: 420px; background: #17171D; border-radius: 16px; padding: 32px;
      border: 2px solid transparent;
      background-image: linear-gradient(#17171D, #17171D), linear-gradient(135deg, #E795FC, #AD2BD7);
      background-origin: border-box; background-clip: padding-box, border-box;
    }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { color: #C7C7D1; font-size: 14px; margin: 0 0 20px; line-height: 1.5; }
    input[type=text] {
      width: 100%; padding: 14px; border-radius: 10px; border: 1px solid #2A2A33;
      background: #2A2A33; color: #F2F2F5; font-size: 16px; margin-bottom: 16px;
    }
    input[type=text]:focus { outline: none; border-color: #AD2BD7; }
    button {
      width: 100%; padding: 14px; border-radius: 10px; border: none; font-size: 16px; font-weight: 600;
      color: #0D0D12; cursor: pointer;
      background: linear-gradient(135deg, #E795FC, #AD2BD7);
    }
    .error { color: #FF8A8A; font-size: 13px; margin: -8px 0 16px; }
''';

/// A tiny LAN HTTP server the TV
/// spins up so a phone on the same network can scan a QR code / visit a
/// URL and push relay-connection info to the TV without typing on a
/// remote. Uses a real HTTP server package (shelf) rather than parsing
/// headers and bodies by hand.
class PairingServer {
  final String prefillNickname;
  final String prefillUrl;
  final void Function(String nickname, String url) onSubmitted;

  PairingServer({this.prefillNickname = '', this.prefillUrl = '', required this.onSubmitted});

  final String _token = _randomToken();
  HttpServer? _server;

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  /// Returns the pairing URL (e.g. http://192.168.1.5:53214/482910), or
  /// null if no non-loopback IPv4 address could be found.
  Future<String?> start() async {
    final ip = await _localIpv4Address();
    if (ip == null) return null;

    final server = await shelf_io.serve(_handle, InternetAddress.anyIPv4, 0);
    _server = server;
    return 'http://$ip:${server.port}/$_token';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<Response> _handle(Request request) async {
    final path = request.url.path;

    if (request.method == 'GET' && path == _token) {
      return _htmlResponse(_formPage());
    }
    if (request.method == 'POST' && path == '$_token/submit') {
      final body = await request.readAsString();
      final fields = _parseFormFields(body);
      final url = fields['url'];
      if (url == null || url.trim().isEmpty) {
        return _htmlResponse(_formPage(error: 'Paste a URL first'));
      }
      final nickname = (fields['nickname']?.trim().isNotEmpty ?? false) ? fields['nickname']!.trim() : 'My relay';
      onSubmitted(nickname, url);
      return _htmlResponse(_successPage());
    }
    return Response.notFound('Not found');
  }

  Response _htmlResponse(String html) => Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});

  Map<String, String> _parseFormFields(String body) {
    final fields = <String, String>{};
    for (final pair in body.split('&')) {
      final parts = pair.split('=');
      if (parts.length != 2) continue;
      fields[parts[0]] = Uri.decodeQueryComponent(parts[1]).trim();
    }
    return fields;
  }

  String _formPage({String? error}) {
    final errorHtml = error != null ? '<p class="error">$error</p>' : '';
    return '''
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Reelay — Pair</title>
<style>$_pairingPageCss</style>
</head><body>
  <div class="card">
    <h1>Reelay</h1>
    <p>Name this relay and paste its URL — both will appear on your TV.</p>
    $errorHtml
    <form method="POST" action="/$_token/submit">
      <input type="text" name="nickname" placeholder="Nickname (e.g. Sean's relay)" value="${_escapeHtmlAttr(prefillNickname)}" autofocus autocomplete="off">
      <input type="text" name="url" placeholder="wss://your-relay-url?token=..." value="${_escapeHtmlAttr(prefillUrl)}" autocomplete="off">
      <button type="submit">Send to TV</button>
    </form>
  </div>
</body></html>
''';
  }

  String _successPage() => '''
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Reelay — Pair</title>
<style>$_pairingPageCss</style>
</head><body>
  <div class="card">
    <h1>Sent ✓</h1>
    <p>Check your TV — the relay should already be filled in. You can close this tab.</p>
  </div>
</body></html>
''';

  Future<String?> _localIpv4Address() async {
    final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }

  String _escapeHtmlAttr(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
