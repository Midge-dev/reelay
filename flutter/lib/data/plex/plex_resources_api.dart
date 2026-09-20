import 'package:dio/dio.dart';

import 'plex_http_client.dart';
import 'plex_models.dart';

class PlexResourcesApi {
  final String clientIdentifier;
  final Dio _client = plexHttpClient();
  final Dio _connectClient = plexHttpClient(timeout: const Duration(milliseconds: 4000));

  PlexResourcesApi(this.clientIdentifier);

  Options _headers(String accountToken) => Options(headers: {
        'X-Plex-Product': 'Reelay',
        'X-Plex-Client-Identifier': clientIdentifier,
        'X-Plex-Token': accountToken,
      });

  /// Unlike most Plex endpoints, this one returns a bare JSON array, not a
  /// MediaContainer-wrapped object.
  Future<List<PlexResource>> fetchResources(String accountToken) async {
    final response = await _client.get<List<dynamic>>(
      'https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1',
      options: _headers(accountToken),
    );
    return (response.data ?? const []).map((e) => PlexResource.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PlexResource>> listServers(String accountToken) async {
    final resources = await fetchResources(accountToken);
    return resources.where((r) => r.provides.contains('server') && r.accessToken != null).toList();
  }

  /// Mirrors Kotlin's `sortedBy { it.owned }`: false sorts before true, so
  /// non-owned (shared) servers are tried first.
  Future<PlexServer?> findReachableServer(String accountToken, {String? preferredMachineIdentifier}) async {
    final servers = await listServers(accountToken);
    if (preferredMachineIdentifier != null) {
      for (final s in servers) {
        if (s.machineIdentifier == preferredMachineIdentifier) return _connectTo(s);
      }
      return null;
    }
    final ordered = [...servers]..sort((a, b) => (a.owned ? 1 : 0).compareTo(b.owned ? 1 : 0));
    for (final resource in ordered) {
      final server = await _connectTo(resource);
      if (server != null) return server;
    }
    return null;
  }

  Future<PlexServer?> _connectTo(PlexResource resource) async {
    final token = resource.accessToken;
    if (token == null) return null;
    final direct = resource.connections.where((c) => !c.relay).toList();
    final relay = resource.connections.where((c) => c.relay).toList();
    final connection = await _firstReachable(direct, token) ?? await _firstReachable(relay, token);
    if (connection == null) return null;
    final baseUrl = connection.uri.endsWith('/') ? connection.uri.substring(0, connection.uri.length - 1) : connection.uri;
    return PlexServer(name: resource.name, baseUrl: baseUrl, accessToken: token);
  }

  Future<PlexConnection?> _firstReachable(List<PlexConnection> candidates, String token) async {
    if (candidates.isEmpty) return null;
    final results = await Future.wait(candidates.map((c) async => (c, await _testConnection(c, token))));
    for (final (connection, reachable) in results) {
      if (reachable) return connection;
    }
    return null;
  }

  Future<bool> _testConnection(PlexConnection connection, String token) async {
    try {
      await _connectClient.get<void>(
        '${connection.uri}/identity',
        options: Options(headers: {'X-Plex-Token': token}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
