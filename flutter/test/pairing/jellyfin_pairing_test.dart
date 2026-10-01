import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_auth_api.dart';
import 'package:reelay/pairing/jellyfin_pairing.dart';
import 'package:reelay/screens/onboarding/jellyfin_link_session.dart';
import 'package:shelf/shelf.dart';

const _base = 'http://loft:8096';

class _FakeServer implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;

  _FakeServer(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key =
        '${options.method} ${options.uri.replace(query: '').toString().replaceFirst(RegExp(r'\?$'), '')}';
    final route = routes[key];
    if (route == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'refused',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(route.$2),
      route.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Map<String, (int, Object?)> routes;
  late JellyfinLinkSession session;
  late JellyfinPairingServer pairing;
  late List<JellyfinSession> linked;

  setUp(() {
    routes = {
      'GET $_base/System/Info/Public': (
        200,
        {
          'ProductName': 'Jellyfin Server',
          'Id': 'server-1',
          'ServerName': 'Loft <3',
          'Version': '12.1.0',
        },
      ),
      'GET $_base/QuickConnect/Enabled': (200, true),
      'POST $_base/QuickConnect/Initiate': (
        200,
        {'Code': '424242', 'Secret': 's1'},
      ),
      'GET $_base/QuickConnect/Connect': (200, {'Authenticated': false}),
      'POST $_base/Users/AuthenticateByName': (
        200,
        {
          'AccessToken': 'pw-token',
          'ServerId': 'server-1',
          'User': {'Id': 'u1', 'Name': 'sam'},
        },
      ),
    };
    linked = [];
    session = JellyfinLinkSession(
      JellyfinAuthApi(
        deviceId: 'd',
        deviceName: 'Android TV',
        appVersion: '0.4.0',
        client: Dio()..httpClientAdapter = _FakeServer(routes),
      ),
      pollInterval: const Duration(milliseconds: 5),
      onLinked: (_, s) => linked.add(s),
    );
    pairing = JellyfinPairingServer(
      session,
      quickConnectWait: const Duration(milliseconds: 500),
    );
  });

  tearDown(() => session.dispose());

  Future<String> get(String path) async =>
      (await pairing.handle(Request('GET', Uri.parse('http://tv/$path'))))
          .readAsString();
  Future<String> post(String path, String body) async => (await pairing.handle(
    Request(
      'POST',
      Uri.parse('http://tv/$path'),
      body: body,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    ),
  )).readAsString();

  test('the QR opens the address form', () async {
    final page = await get(pairing.token);
    expect(page, contains('Link your Jellyfin server'));
    expect(page, contains('name="address"'));
    expect(page, contains('JELLYFIN'));
  });

  test('a good address leads to Quick Connect and the password form', () async {
    final page = await post('${pairing.token}/server', 'address=loft');
    expect(
      page,
      contains('Sign in to Loft &lt;3'),
      reason: 'server names are escaped',
    );
    expect(page, contains('href="$_base/web/#/quickconnect?code=424242"'));
    expect(page, contains('name="username"'));
    expect(session.server?.id, 'server-1');
  });

  test('a bad address stays on the form and names the cause', () async {
    final page = await post('${pairing.token}/server', 'address=nowhere');
    expect(page, contains('name="address"'));
    expect(page, contains('value="nowhere"'));
    expect(
      page,
      contains(
        jellyfinFailureMessage(JellyfinAuthFailure.unreachable)
            .replaceAll('’', '’'),
      ),
    );
  });

  test('signing in from the phone links the TV', () async {
    await post('${pairing.token}/server', 'address=loft');
    final page = await post(
      '${pairing.token}/signin',
      'username=sam&password=pw',
    );
    expect(page, contains('is linked on your TV'));
    expect(linked.single.accessToken, 'pw-token');
  });

  test('a refused password keeps the username and says why', () async {
    routes['POST $_base/Users/AuthenticateByName'] = (401, null);
    await post('${pairing.token}/server', 'address=loft');
    final page = await post(
      '${pairing.token}/signin',
      'username=sam&password=nope',
    );
    expect(page, contains('value="sam"'));
    expect(page, contains('didn’t accept that username and password'));
    expect(linked, isEmpty);
  });

  test(
    'coming back to the page resumes at the account step, or changes server',
    () async {
      await post('${pairing.token}/server', 'address=loft');
      expect(await get(pairing.token), contains('Sign in to Loft'));
      expect(await get('${pairing.token}?change'), contains('name="address"'));
    },
  );

  test('a wrong token is not found', () async {
    final response = await pairing.handle(
      Request('GET', Uri.parse('http://tv/000000x')),
    );
    expect(response.statusCode, 404);
  });
}
