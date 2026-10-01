import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _defaultTimeout = Duration(milliseconds: 15000);

/// Jellyfin's own port. A typed address without one tries it first.
const jellyfinDefaultPort = 8096;

/// How this TV is named in the server's device list.
String get jellyfinDeviceName => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => 'Apple TV',
  TargetPlatform.macOS => 'Mac',
  _ => 'Android TV',
};

/// Why linking a Jellyfin server failed — each one is a different thing for
/// the person at the TV to fix, so screens name it rather than "error".
enum JellyfinAuthFailure {
  /// Nothing answered at the address.
  unreachable,

  /// Something answered, but it isn't a Jellyfin server.
  notJellyfin,

  /// A Jellyfin server whose first-run wizard hasn't been finished, so it
  /// has no users to sign in as yet.
  notSetUp,

  /// The server refused the username and password.
  wrongCredentials,

  /// The server has Quick Connect switched off (Dashboard → General).
  quickConnectDisabled,

  /// The Quick Connect code timed out before anyone approved it.
  quickConnectExpired,
}

class JellyfinAuthException implements Exception {
  final JellyfinAuthFailure failure;
  final Object? cause;

  const JellyfinAuthException(this.failure, [this.cause]);

  @override
  String toString() =>
      'JellyfinAuthException($failure${cause == null ? '' : ': $cause'})';
}

/// A server that answered `/System/Info/Public` as Jellyfin.
class JellyfinServerInfo {
  /// The address that answered — what every later request goes to.
  final String baseUrl;

  /// Jellyfin's `ServerId`: stable across address changes.
  final String id;
  final String name;
  final String version;

  const JellyfinServerInfo({
    required this.baseUrl,
    required this.id,
    required this.name,
    required this.version,
  });
}

/// A signed-in user on one server: what `AuthenticateByName` and
/// `AuthenticateWithQuickConnect` both return.
class JellyfinSession {
  final String accessToken;
  final String userId;
  final String userName;
  final String serverId;

  const JellyfinSession({
    required this.accessToken,
    required this.userId,
    required this.userName,
    required this.serverId,
  });

  factory JellyfinSession.fromJson(Map<String, dynamic> json) {
    final user = json['User'] as Map<String, dynamic>? ?? const {};
    return JellyfinSession(
      accessToken: json['AccessToken'] as String,
      userId: user['Id'] as String,
      userName: user['Name'] as String? ?? '',
      serverId:
          json['ServerId'] as String? ?? user['ServerId'] as String? ?? '',
    );
  }
}

/// A Quick Connect request in flight: [code] is what the person approves
/// on another signed-in device; [secret] is what this TV polls with.
class JellyfinQuickConnect {
  final String code;
  final String secret;

  const JellyfinQuickConnect({required this.code, required this.secret});
}

/// The addresses to try, best first, for what someone typed as a server
/// address. People type "loft", "192.168.0.10:8096", or paste the browser's
/// "http://loft:8096/web/#/home" — all of those should find the server.
List<String> jellyfinAddressCandidates(String typed) {
  var address = typed.trim();
  // The web app's own path, from a pasted browser URL.
  final web = RegExp(r'/web(/.*)?$|/#.*$');
  address = address.replaceFirst(web, '');
  while (address.endsWith('/')) {
    address = address.substring(0, address.length - 1);
  }
  if (address.isEmpty) return const [];

  final hasScheme =
      address.startsWith('http://') || address.startsWith('https://');
  if (hasScheme) return [address];

  // Host and optional port, with any reverse-proxy path after it.
  final slash = address.indexOf('/');
  final host = slash == -1 ? address : address.substring(0, slash);
  final hasPort = RegExp(r':\d+$').hasMatch(host);
  if (hasPort) return ['http://$address', 'https://$address'];
  final path = slash == -1 ? '' : address.substring(slash);
  return [
    'http://$host:$jellyfinDefaultPort$path',
    'https://$address',
    'http://$address',
  ];
}

/// Signing a TV in to a Jellyfin server. Every call names this install to
/// the server — Jellyfin lists it under Dashboard → Devices and ties the
/// token it issues to [deviceId].
class JellyfinAuthApi {
  final String deviceId;
  final String deviceName;
  final String appVersion;
  final Dio _client;

  JellyfinAuthApi({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    Dio? client,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: _defaultTimeout,
               receiveTimeout: _defaultTimeout,
               headers: const {'Accept': 'application/json'},
             ),
           );

  /// Jellyfin's client identity header. [token] makes it an authenticated
  /// one; the same header carries both.
  String authorization({String? token}) {
    String quoted(String value) => '"${Uri.encodeComponent(value)}"';
    return 'MediaBrowser Client=${quoted('Reelay')}, Device=${quoted(deviceName)}, '
        'DeviceId=${quoted(deviceId)}, Version=${quoted(appVersion)}'
        '${token == null ? '' : ', Token=${quoted(token)}'}';
  }

  Options _options({String? token}) =>
      Options(headers: {'Authorization': authorization(token: token)});

  /// Finds the server behind what someone typed: the first candidate
  /// address (see [jellyfinAddressCandidates]) that answers as Jellyfin.
  /// Tested before asking for an account, so a typo is caught on its own.
  Future<JellyfinServerInfo> probe(String typedAddress) async {
    JellyfinAuthException? notJellyfin;
    for (final baseUrl in jellyfinAddressCandidates(typedAddress)) {
      final Response<dynamic> response;
      try {
        response = await _client.get<dynamic>(
          '$baseUrl/System/Info/Public',
          options: _options(),
        );
      } on DioException catch (e) {
        if (e.response != null) {
          notJellyfin ??= JellyfinAuthException(
            JellyfinAuthFailure.notJellyfin,
            e,
          );
        }
        continue;
      }
      final json = response.data;
      if (json is! Map<String, dynamic> ||
          json['Id'] is! String ||
          json['ProductName'] != 'Jellyfin Server') {
        notJellyfin ??= const JellyfinAuthException(
          JellyfinAuthFailure.notJellyfin,
        );
        continue;
      }
      if (json['StartupWizardCompleted'] == false) {
        throw const JellyfinAuthException(JellyfinAuthFailure.notSetUp);
      }
      return JellyfinServerInfo(
        baseUrl: baseUrl,
        id: json['Id'] as String,
        name: json['ServerName'] as String? ?? 'Jellyfin',
        version: json['Version'] as String? ?? '',
      );
    }
    throw notJellyfin ??
        const JellyfinAuthException(JellyfinAuthFailure.unreachable);
  }

  Future<JellyfinSession> signIn(
    String baseUrl, {
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$baseUrl/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: _options(),
      );
      return JellyfinSession.fromJson(response.data!);
    } on DioException catch (e) {
      throw _failure(e, onRefused: JellyfinAuthFailure.wrongCredentials);
    }
  }

  Future<bool> isQuickConnectEnabled(String baseUrl) async {
    try {
      final response = await _client.get<dynamic>(
        '$baseUrl/QuickConnect/Enabled',
        options: _options(),
      );
      return response.data == true;
    } on DioException {
      return false;
    }
  }

  /// Starts a Quick Connect request. Show [JellyfinQuickConnect.code];
  /// then [quickConnectApproved] until it's approved.
  Future<JellyfinQuickConnect> startQuickConnect(String baseUrl) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$baseUrl/QuickConnect/Initiate',
        options: _options(),
      );
      final json = response.data!;
      return JellyfinQuickConnect(
        code: json['Code'] as String,
        secret: json['Secret'] as String,
      );
    } on DioException catch (e) {
      // A server with Quick Connect off refuses to start one.
      throw _failure(e, onRefused: JellyfinAuthFailure.quickConnectDisabled);
    }
  }

  /// Whether the code has been approved yet. Poll every few seconds.
  Future<bool> quickConnectApproved(String baseUrl, String secret) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '$baseUrl/QuickConnect/Connect',
        queryParameters: {'secret': secret},
        options: _options(),
      );
      return response.data?['Authenticated'] == true;
    } on DioException catch (e) {
      // The server forgets a secret once it expires.
      if (e.response?.statusCode == 404) {
        throw JellyfinAuthException(JellyfinAuthFailure.quickConnectExpired, e);
      }
      throw _failure(e, onRefused: JellyfinAuthFailure.quickConnectExpired);
    }
  }

  /// Exchanges an approved Quick Connect [secret] for a session.
  Future<JellyfinSession> finishQuickConnect(
    String baseUrl,
    String secret,
  ) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$baseUrl/Users/AuthenticateWithQuickConnect',
        data: {'Secret': secret},
        options: _options(),
      );
      return JellyfinSession.fromJson(response.data!);
    } on DioException catch (e) {
      throw _failure(e, onRefused: JellyfinAuthFailure.quickConnectExpired);
    }
  }

  /// Ends the session server-side, so the device drops off the server's
  /// list. Best effort: unlinking goes ahead whether or not it's reachable.
  Future<void> signOut(String baseUrl, String token) async {
    try {
      await _client.post<void>(
        '$baseUrl/Sessions/Logout',
        options: _options(token: token),
      );
    } on DioException catch (e) {
      debugPrint('Jellyfin sign-out failed: $e');
    }
  }

  JellyfinAuthException _failure(
    DioException e, {
    required JellyfinAuthFailure onRefused,
  }) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return JellyfinAuthException(onRefused, e);
    }
    if (e.response == null) {
      return JellyfinAuthException(JellyfinAuthFailure.unreachable, e);
    }
    return JellyfinAuthException(JellyfinAuthFailure.notJellyfin, e);
  }
}

/// Jellyfin refusing a saved token — the device was removed under
/// Dashboard → Devices, or the user's password changed. Only linking again
/// can fix it.
bool isJellyfinSignInRevoked(Object error) =>
    error is DioException && error.response?.statusCode == 401;
