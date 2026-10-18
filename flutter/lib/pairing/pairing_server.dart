import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../theme/tokens.dart';
import 'pairing_page.dart';

/// A tiny LAN HTTP server the TV
/// spins up so a phone on the same network can scan a QR code / visit a
/// URL and push relay-connection info to the TV without typing on a
/// remote. Uses a real HTTP server package (shelf) rather than parsing
/// headers and bodies by hand.
class PairingServer {
  final String prefillNickname;
  final String prefillUrl;
  final void Function(String nickname, String url) onSubmitted;

  PairingServer({
    this.prefillNickname = '',
    this.prefillUrl = '',
    required this.onSubmitted,
  });

  final String _token = randomPairingToken();
  HttpServer? _server;

  /// Returns the pairing URL (e.g. http://192.168.1.5:53214/482910), or
  /// null if no non-loopback IPv4 address could be found.
  Future<String?> start() async {
    final ip = await localIpv4Address();
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
      final fields = parseFormFields(body);
      final url = fields['url'];
      if (url == null || url.trim().isEmpty) {
        return _htmlResponse(
          _formPage(error: "Paste the relay's address first."),
        );
      }
      final nickname = (fields['nickname']?.trim().isNotEmpty ?? false)
          ? fields['nickname']!.trim()
          : 'My relay';
      onSubmitted(nickname, url);
      return _htmlResponse(_successPage());
    }
    return Response.notFound('Not found');
  }

  Response _htmlResponse(String html) => pairingHtmlResponse(html);

  String _formPage({String? error}) => pairingFormPage(
    theme: AppColors.currentTheme,
    action: '/$_token/submit',
    nickname: prefillNickname,
    url: prefillUrl,
    editing: prefillUrl.isNotEmpty,
    error: error,
  );

  String _successPage() => pairingSentPage(theme: AppColors.currentTheme);
}

/// The path segment that keeps a pairing page private to whoever can see
/// the TV: six random digits.
String randomPairingToken() {
  final random = Random.secure();
  return List.generate(6, (_) => random.nextInt(10)).join();
}

/// This TV's address on the local network, or null when it has none.
Future<String?> localIpv4Address() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return null;
}

/// A posted form's fields, trimmed.
Map<String, String> parseFormFields(String body) {
  final fields = <String, String>{};
  for (final pair in body.split('&')) {
    final parts = pair.split('=');
    if (parts.length != 2) continue;
    fields[parts[0]] = Uri.decodeQueryComponent(parts[1]).trim();
  }
  return fields;
}

Response pairingHtmlResponse(String html) => Response.ok(
  html,
  headers: {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
  },
);
