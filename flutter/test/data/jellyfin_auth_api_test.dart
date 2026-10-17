import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_auth_api.dart';

/// Answers each request from [routes], keyed "METHOD url-without-query";
/// anything unrouted fails as if nothing were listening.
class _FakeServer implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final requests = <RequestOptions>[];

  _FakeServer(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final route = routes['${options.method} ${options.uri.replace(query: '').toString().replaceFirst(RegExp(r'\?$'), '')}'];
    if (route == null) {
      throw DioException.connectionError(requestOptions: options, reason: 'refused');
    }
    final (status, body) = route;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _publicInfo = {
  'LocalAddress': 'http://172.17.0.2:8096',
  'ServerName': 'Loft',
  'Version': '12.1.0',
  'ProductName': 'Jellyfin Server',
  'Id': 'server-1',
  'StartupWizardCompleted': true,
};

const _authResult = {
  'User': {'Id': 'user-1', 'Name': 'sam', 'ServerId': 'server-1'},
  'AccessToken': 'token-1',
  'ServerId': 'server-1',
};

(JellyfinAuthApi, _FakeServer) _api(Map<String, (int, Object?)> routes) {
  final server = _FakeServer(routes);
  final dio = Dio()..httpClientAdapter = server;
  return (JellyfinAuthApi(deviceId: 'device-1', deviceName: 'Android TV', appVersion: '0.4.0', client: dio), server);
}

void main() {
  group('server address', () {
    test('a bare host tries Jellyfin\'s own port first', () {
      expect(jellyfinAddressCandidates('loft'), ['http://loft:8096', 'https://loft', 'http://loft']);
    });

    test('a host with a port keeps it, plain then TLS', () {
      expect(jellyfinAddressCandidates(' 192.168.0.10:8096 '), ['http://192.168.0.10:8096', 'https://192.168.0.10:8096']);
    });

    test('a full URL is used as typed', () {
      expect(jellyfinAddressCandidates('https://media.example.com'), ['https://media.example.com']);
    });

    test("a pasted browser URL loses the web app's path", () {
      expect(jellyfinAddressCandidates('http://loft:8096/web/#/home.html'), ['http://loft:8096']);
      expect(jellyfinAddressCandidates('http://loft:8096/web/'), ['http://loft:8096']);
    });

    test('a reverse-proxy path survives', () {
      expect(jellyfinAddressCandidates('https://example.com/jellyfin/'), ['https://example.com/jellyfin']);
      expect(jellyfinAddressCandidates('example.com/jellyfin'), [
        'http://example.com:8096/jellyfin',
        'https://example.com/jellyfin',
        'http://example.com/jellyfin',
      ]);
    });

    test('nothing typed is nothing to try', () {
      expect(jellyfinAddressCandidates('  / '), isEmpty);
    });
  });

  test('every request names this TV to the server', () async {
    final (api, server) = _api({'GET http://loft:8096/System/Info/Public': (200, _publicInfo)});
    await api.probe('loft');
    expect(
      server.requests.single.headers['Authorization'],
      'MediaBrowser Client="Reelay", Device="Android%20TV", DeviceId="device-1", Version="0.4.0"',
    );
    expect(api.authorization(token: 'tok'), endsWith(', Token="tok"'));
  });

  group('probe', () {
    test('finds the server at the first address that answers', () async {
      final (api, _) = _api({'GET https://loft/System/Info/Public': (200, _publicInfo)});
      final info = await api.probe('loft');
      expect(info.baseUrl, 'https://loft');
      expect(info.id, 'server-1');
      expect(info.name, 'Loft');
      expect(info.version, '12.1.0');
    });

    test('nothing listening is unreachable', () async {
      final (api, _) = _api({});
      await expectLater(api.probe('loft'), throwsA(_failure(JellyfinAuthFailure.unreachable)));
    });

    test('something that is not Jellyfin says so', () async {
      final (api, _) = _api({'GET http://loft:8096/System/Info/Public': (404, {'error': 'nope'})});
      await expectLater(api.probe('loft'), throwsA(_failure(JellyfinAuthFailure.notJellyfin)));

      final (other, _) = _api({
        'GET http://loft:8096/System/Info/Public': (200, {'ProductName': 'Emby Server', 'Id': 'x'}),
      });
      await expectLater(other.probe('loft'), throwsA(_failure(JellyfinAuthFailure.notJellyfin)));
    });

    test('a server still in its first-run wizard has no one to sign in as', () async {
      final (api, _) = _api({
        'GET http://loft:8096/System/Info/Public': (200, {..._publicInfo, 'StartupWizardCompleted': false}),
      });
      await expectLater(api.probe('loft'), throwsA(_failure(JellyfinAuthFailure.notSetUp)));
    });
  });

  group('sign in', () {
    test('a username and password become a session', () async {
      final (api, server) = _api({'POST http://loft:8096/Users/AuthenticateByName': (200, _authResult)});
      final session = await api.signIn('http://loft:8096', username: 'sam', password: 'pw');
      expect(session.accessToken, 'token-1');
      expect(session.deviceId, 'device-1', reason: 'kept with the link: the token is only good for it');
      expect(session.userId, 'user-1');
      expect(session.userName, 'sam');
      expect(session.serverId, 'server-1');
      expect(server.requests.single.data, {'Username': 'sam', 'Pw': 'pw'});
    });

    test('a refused password is wrong credentials, not a network error', () async {
      final (api, _) = _api({'POST http://loft:8096/Users/AuthenticateByName': (401, null)});
      await expectLater(
        api.signIn('http://loft:8096', username: 'sam', password: 'nope'),
        throwsA(_failure(JellyfinAuthFailure.wrongCredentials)),
      );
    });
  });

  group('Quick Connect', () {
    const base = 'http://loft:8096';

    test('start, wait for approval, then finish', () async {
      final routes = <String, (int, Object?)>{
        'GET $base/QuickConnect/Enabled': (200, true),
        'POST $base/QuickConnect/Initiate': (200, {'Code': '123456', 'Secret': 'sec', 'Authenticated': false}),
        'GET $base/QuickConnect/Connect': (200, {'Authenticated': false}),
        'POST $base/Users/AuthenticateWithQuickConnect': (200, _authResult),
      };
      final (api, server) = _api(routes);

      expect(await api.isQuickConnectEnabled(base), isTrue);
      final request = await api.startQuickConnect(base);
      expect(request.code, '123456');
      expect(await api.quickConnectApproved(base, request.secret), isFalse);
      expect(server.requests.last.queryParameters, {'secret': 'sec'});

      routes['GET $base/QuickConnect/Connect'] = (200, {'Authenticated': true});
      expect(await api.quickConnectApproved(base, request.secret), isTrue);

      final session = await api.finishQuickConnect(base, request.secret);
      expect(session.accessToken, 'token-1');
      expect(session.deviceId, 'device-1', reason: 'kept with the link: the token is only good for it');
      expect(server.requests.last.data, {'Secret': 'sec'});
    });

    test('switched off on the server', () async {
      final (api, _) = _api({
        'GET $base/QuickConnect/Enabled': (200, false),
        'POST $base/QuickConnect/Initiate': (401, null),
      });
      expect(await api.isQuickConnectEnabled(base), isFalse);
      await expectLater(api.startQuickConnect(base), throwsA(_failure(JellyfinAuthFailure.quickConnectDisabled)));
    });

    test('an unreachable server has no Quick Connect to offer', () async {
      final (api, _) = _api({});
      expect(await api.isQuickConnectEnabled(base), isFalse);
    });

    test('a code nobody approved in time expires', () async {
      final (api, _) = _api({'GET $base/QuickConnect/Connect': (404, null)});
      await expectLater(
        api.quickConnectApproved(base, 'old'),
        throwsA(_failure(JellyfinAuthFailure.quickConnectExpired)),
      );
    });
  });

  test('signing out of an unreachable server does not throw', () async {
    final (api, server) = _api({});
    await api.signOut('http://loft:8096', 'tok');
    expect(server.requests.single.headers['Authorization'], contains('Token="tok"'));
  });

  test('a 401 on a saved token means the sign-in was revoked', () {
    final options = RequestOptions(path: '/Users/Me');
    expect(
      isJellyfinSignInRevoked(
        DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: 401)),
      ),
      isTrue,
    );
    expect(isJellyfinSignInRevoked(DioException.connectionError(requestOptions: options, reason: 'x')), isFalse);
  });
}

Matcher _failure(JellyfinAuthFailure failure) =>
    isA<JellyfinAuthException>().having((e) => e.failure, 'failure', failure);
