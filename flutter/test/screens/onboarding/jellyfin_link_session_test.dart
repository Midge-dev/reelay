import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_auth_api.dart';
import 'package:reelay/screens/onboarding/jellyfin_link_session.dart';

const _base = 'http://loft:8096';

class _FakeServer implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final hits = <String>[];

  _FakeServer(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = '${options.method} ${options.uri.replace(query: '').toString().replaceFirst(RegExp(r'\?$'), '')}';
    hits.add(key);
    final route = routes[key];
    if (route == null) throw DioException.connectionError(requestOptions: options, reason: 'refused');
    return ResponseBody.fromString(jsonEncode(route.$2), route.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, (int, Object?)> _routes({bool quickConnect = true}) => {
  'GET $_base/System/Info/Public': (
    200,
    {'ProductName': 'Jellyfin Server', 'Id': 'server-1', 'ServerName': 'Loft', 'Version': '12.1.0'},
  ),
  'GET $_base/QuickConnect/Enabled': (200, quickConnect),
  'POST $_base/QuickConnect/Initiate': (200, {'Code': '111111', 'Secret': 's1'}),
  'GET $_base/QuickConnect/Connect': (200, {'Authenticated': false}),
  'POST $_base/Users/AuthenticateWithQuickConnect': (
    200,
    {'AccessToken': 'qc-token', 'ServerId': 'server-1', 'User': {'Id': 'u1', 'Name': 'sam'}},
  ),
  'POST $_base/Users/AuthenticateByName': (
    200,
    {'AccessToken': 'pw-token', 'ServerId': 'server-1', 'User': {'Id': 'u1', 'Name': 'sam'}},
  ),
};

/// Lets the session's Quick Connect loop take a few turns.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late Map<String, (int, Object?)> routes;
  late _FakeServer fake;
  late List<JellyfinSession> linked;
  late JellyfinLinkSession session;

  void build({bool quickConnect = true}) {
    routes = _routes(quickConnect: quickConnect);
    fake = _FakeServer(routes);
    linked = [];
    session = JellyfinLinkSession(
      JellyfinAuthApi(
        deviceId: 'd',
        deviceName: 'Android TV',
        appVersion: '0.4.0',
        client: Dio()..httpClientAdapter = fake,
      ),
      pollInterval: const Duration(milliseconds: 1),
      onLinked: (_, s) => linked.add(s),
    );
  }

  tearDown(() => session.dispose());

  test('a good address becomes the server, with a Quick Connect code to approve', () async {
    build();
    expect(await session.useAddress('loft'), isNull);
    expect(session.server?.name, 'Loft');
    await _settle();
    expect(session.quickConnect?.code, '111111');
    expect(linked, isEmpty);
  });

  test('approving the code links the account', () async {
    build();
    await session.useAddress('loft');
    await _settle();
    routes['GET $_base/QuickConnect/Connect'] = (200, {'Authenticated': true});
    await _settle();
    expect(linked.single.accessToken, 'qc-token');
    expect(session.linked, isTrue);
  });

  test('a username and password link the account', () async {
    build();
    await session.useAddress('loft');
    expect(await session.signIn('sam', 'pw'), isNull);
    expect(linked.single.accessToken, 'pw-token');
    expect(session.username, 'sam');
  });

  test('a refused password says so, and leaves the session open', () async {
    build();
    await session.useAddress('loft');
    routes['POST $_base/Users/AuthenticateByName'] = (401, null);
    expect(await session.signIn('sam', 'nope'), JellyfinAuthFailure.wrongCredentials);
    expect(session.failure, JellyfinAuthFailure.wrongCredentials);
    expect(session.linked, isFalse);
  });

  test('a bad address names why, and keeps no server', () async {
    build();
    expect(await session.useAddress('nowhere'), JellyfinAuthFailure.unreachable);
    expect(session.server, isNull);
    expect(session.failure, JellyfinAuthFailure.unreachable);
  });

  test('an expired code is replaced with a fresh one', () async {
    build();
    await session.useAddress('loft');
    await _settle();
    expect(session.quickConnect?.code, '111111');
    routes['POST $_base/QuickConnect/Initiate'] = (200, {'Code': '222222', 'Secret': 's2'});
    routes['GET $_base/QuickConnect/Connect'] = (404, null);
    await _settle();
    expect(session.quickConnect?.code, '222222');
  });

  test('with Quick Connect off there is no code, and the password still works', () async {
    build(quickConnect: false);
    await session.useAddress('loft');
    await _settle();
    expect(session.quickConnect, isNull);
    expect(fake.hits, isNot(contains('POST $_base/QuickConnect/Initiate')));
    expect(await session.signIn('sam', 'pw'), isNull);
    expect(linked, hasLength(1));
  });

  test('whichever way finishes first wins; the other is ignored', () async {
    build();
    await session.useAddress('loft');
    await session.signIn('sam', 'pw');
    routes['GET $_base/QuickConnect/Connect'] = (200, {'Authenticated': true});
    await _settle();
    expect(linked, hasLength(1));
    expect(await session.signIn('sam', 'pw'), isNull);
    expect(linked, hasLength(1));
  });

  test('ending the session stops polling', () async {
    build();
    await session.useAddress('loft');
    await _settle();
    session.dispose();
    final before = fake.hits.length;
    await _settle();
    expect(fake.hits.length, lessThanOrEqualTo(before + 1));
    build(); // tearDown disposes this one
  });
}
