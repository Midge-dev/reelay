import 'package:dio/dio.dart';

const _defaultTimeout = Duration(milliseconds: 15000);

/// Ports shared/.../data/plex/PlexHttpClient.kt's `plexHttpClient()`. dio
/// throws DioException on non-2xx by default (matching Ktor's
/// `expectSuccess = true`), and decodes JSON bodies to Map/List
/// automatically — callers still run the result through a model's
/// `fromJson`, same shape as the Kotlin client's `.body<T>()`.
Dio plexHttpClient({Duration timeout = _defaultTimeout}) {
  return Dio(
    BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: const {'Accept': 'application/json'},
    ),
  );
}
