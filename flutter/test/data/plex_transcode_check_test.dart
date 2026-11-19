import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/plex/plex_client.dart';
import 'package:reelay/data/plex/plex_playback_urls.dart';

/// Answers every request with [status] and [body]; [body] null means the
/// server isn't there at all.
class _Answer implements HttpClientAdapter {
  _Answer(this.status, this.body);
  final int status;
  final Object? body;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri);
    if (body == null) throw DioException.connectionError(requestOptions: options, reason: 'refused');
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _server = MediaServer(name: 'ScreamTiki', baseUrl: 'http://10.0.0.2:32400', accessToken: 'tok');

void main() {
  final start = plexTranscodeUrl(_server, '100', maxVideoBitrateKbps: 8000, clientIdentifier: 'c', sessionIdentifier: 'p', sessionId: 's');

  (PlexClient, _Answer) client(int status, Object? body) {
    final answer = _Answer(status, body);
    return (PlexClient(_server, 'c', client: Dio()..httpClientAdapter = answer), answer);
  }

  test('a transcode Plex will do: go ahead', () async {
    final (plex, answer) = client(200, {'MediaContainer': {'generalDecisionCode': 1001, 'transcodeDecisionCode': 1001}});
    expect(await plex.checkTranscode(start), isNull);
    expect(answer.requested.single.path, '/video/:/transcode/universal/decision');
  });

  test("one it won't: its reason, even on a 400", () async {
    final (plex, _) = client(400, {
      'MediaContainer': {'generalDecisionCode': 2000, 'generalDecisionText': 'Remote stream limit reached'},
    });
    expect(await plex.checkTranscode(start), 'Remote stream limit reached');
  });

  test('a bare 400 still counts as a refusal', () async {
    final (plex, _) = client(400, 'Bad Request');
    expect(await plex.checkTranscode(start), 'answered 400');
  });

  test("a server that doesn't answer the question doesn't block the stream", () async {
    final (plex, _) = client(0, null);
    expect(await plex.checkTranscode(start), isNull);
  });

  test('stopping asks Plex to end that session', () async {
    final (plex, answer) = client(200, {});
    await plex.stopTranscode('s');
    expect(answer.requested.single.path, '/video/:/transcode/universal/stop');
    expect(answer.requested.single.queryParameters['session'], 's');
  });
}
