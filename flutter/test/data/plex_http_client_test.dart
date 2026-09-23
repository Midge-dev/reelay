import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_http_client.dart';

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/api/v2/resources'),
  response: Response(requestOptions: RequestOptions(path: '/api/v2/resources'), statusCode: code),
  type: DioExceptionType.badResponse,
);

void main() {
  test('a 401 from Plex means the sign-in was revoked', () {
    expect(isPlexSignInRevoked(_status(401)), isTrue);
  });

  test('other failures are not a revoked sign-in', () {
    expect(isPlexSignInRevoked(_status(500)), isFalse);
    expect(isPlexSignInRevoked(DioException.connectionTimeout(timeout: Duration.zero, requestOptions: RequestOptions())), isFalse);
    expect(isPlexSignInRevoked(StateError('x')), isFalse);
  });
}
