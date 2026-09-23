import 'package:dio/dio.dart';

const _defaultTimeout = Duration(milliseconds: 15000);

/// The shared Plex HTTP client. dio throws DioException on non-2xx by
/// default and decodes JSON bodies to Map/List automatically — callers run
/// the result through a model's `fromJson`.
Dio plexHttpClient({Duration timeout = _defaultTimeout}) {
  return Dio(
    BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: const {'Accept': 'application/json'},
    ),
  );
}
