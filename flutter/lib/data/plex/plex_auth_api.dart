import 'package:dio/dio.dart';

import 'plex_http_client.dart';

class PlexPin {
  final int id;
  final String code;
  final String? authToken;
  final int expiresIn;

  const PlexPin({required this.id, required this.code, this.authToken, this.expiresIn = 0});

  factory PlexPin.fromJson(Map<String, dynamic> json) => PlexPin(
        id: json['id'] as int,
        code: json['code'] as String,
        authToken: json['authToken'] as String?,
        expiresIn: json['expiresIn'] as int? ?? 0,
      );
}

class PlexAccount {
  final String username;
  final String? thumb;

  const PlexAccount({required this.username, this.thumb});
}

class PlexAuthApi {
  final String clientIdentifier;
  final Dio _client = plexHttpClient();

  PlexAuthApi(this.clientIdentifier);

  Options get _headers => Options(headers: {
        'X-Plex-Product': 'Reelay',
        'X-Plex-Client-Identifier': clientIdentifier,
      });

  Options _headersWithToken(String token) => Options(headers: {
        'X-Plex-Product': 'Reelay',
        'X-Plex-Client-Identifier': clientIdentifier,
        'X-Plex-Token': token,
      });

  Future<PlexPin> createPin() async {
    final response = await _client.post<Map<String, dynamic>>(
      'https://plex.tv/api/v2/pins',
      options: _headers.copyWith(contentType: Headers.formUrlEncodedContentType),
      data: '',
    );
    return PlexPin.fromJson(response.data!);
  }

  Future<PlexPin> pollPin(int id) async {
    final response = await _client.get<Map<String, dynamic>>(
      'https://plex.tv/api/v2/pins/$id',
      options: _headers,
    );
    return PlexPin.fromJson(response.data!);
  }

  Future<PlexAccount> fetchAccount(String authToken) async {
    final response = await _client.get<Map<String, dynamic>>(
      'https://plex.tv/api/v2/user',
      options: _headersWithToken(authToken),
    );
    final json = response.data!;
    final username = json['username'] as String? ?? json['title'] as String? ?? 'Plex user';
    return PlexAccount(username: username, thumb: json['thumb'] as String?);
  }
}
