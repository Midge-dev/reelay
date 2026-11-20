import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/plex/plex_client.dart';
import 'package:reelay/playback/skip_markers.dart';

class _Answer implements HttpClientAdapter {
  _Answer(this.body);
  final Object body;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _server = MediaServer(name: 'ScreamTiki', baseUrl: 'http://10.0.0.2:32400', accessToken: 'tok');

void main() {
  group('Plex', () {
    (PlexClient, _Answer) plex(Map<String, Object?> item) {
      final answer = _Answer({
        'MediaContainer': {
          'Metadata': [item],
        },
      });
      return (PlexClient(_server, 'c', client: Dio()..httpClientAdapter = answer), answer);
    }

    test("the server's own intro and credits markers, asked for with the episode", () async {
      final (client, answer) = plex({
        'ratingKey': '100',
        'duration': 2700000,
        'Marker': [
          {'type': 'intro', 'startTimeOffset': 30000, 'endTimeOffset': 95000},
          {'type': 'commercial', 'startTimeOffset': 1000000, 'endTimeOffset': 1100000},
          {'type': 'credits', 'startTimeOffset': 2580000, 'endTimeOffset': 2700000, 'final': true},
        ],
        'Chapter': [
          {'tag': 'Opening', 'startTimeOffset': 0, 'endTimeOffset': 60000},
        ],
      });
      expect(await client.fetchSkipMarkers('100'), const [
        SkipMarker(SkipKind.intro, 30000, 95000),
        SkipMarker(SkipKind.credits, 2580000, 2700000),
      ], reason: "markers win over chapters, and other kinds aren't ours");
      final asked = answer.requested.single;
      expect(asked.path, '/library/metadata/100');
      expect(asked.queryParameters, containsPair('includeMarkers', '1'));
    });

    test('no markers (no Plex Pass, or detection off): chapters named for them', () async {
      final (client, _) = plex({
        'duration': 2700000,
        'Chapter': [
          {'tag': 'Cold open', 'startTimeOffset': 0, 'endTimeOffset': 120000},
          {'tag': 'Opening Credits', 'startTimeOffset': 120000, 'endTimeOffset': 180000},
          {'tag': 'Chapter 3', 'startTimeOffset': 180000, 'endTimeOffset': 2550000},
          {'tag': 'End Credits', 'startTimeOffset': 2550000},
        ],
      });
      expect(await client.fetchSkipMarkers('100'), const [
        SkipMarker(SkipKind.intro, 120000, 180000),
        SkipMarker(SkipKind.credits, 2550000, 2700000),
      ], reason: '"Opening Credits" is the intro; the last chapter runs to the end');
    });

    test('neither: nothing', () async {
      final (client, _) = plex({'duration': 2700000});
      expect(await client.fetchSkipMarkers('100'), isEmpty);
    });
  });

  group('chapter names', () {
    List<SkipKind> kinds(List<String> names) => [
      for (final m in markersFromChapters([
        for (var i = 0; i < names.length; i++) (title: names[i], startMs: i * 1000, endMs: null),
      ], durationMs: names.length * 1000))
        m.kind,
    ];

    test('read as an intro', () {
      expect(kinds(['Intro', 'Introduction', 'Opening', 'Opening Credits', 'OP', 'OP1']), List.filled(6, SkipKind.intro));
    });

    test('read as the credits', () {
      expect(kinds(['Credits', 'End Credits', 'Outro', 'Closing', 'Ending', 'ED', 'ED 2']), List.filled(7, SkipKind.credits));
    });

    test('and not', () {
      expect(kinds(['Chapter 1', 'The Opener', 'Opportunity', 'Edward', 'Prologue', '']), isEmpty);
    });
  });

  group('where the credits start', () {
    test('the last credits marker', () {
      expect(creditsStartMs(const [SkipMarker(SkipKind.intro, 0, 60000), SkipMarker(SkipKind.credits, 2500000, 2700000)], 2700000), 2500000);
    });

    test("not in the first half — a mislabelled chapter mustn't bring Up Next mid-episode", () {
      expect(creditsStartMs(const [SkipMarker(SkipKind.credits, 120000, 180000)], 2700000), isNull);
    });

    test('none', () {
      expect(creditsStartMs(const [SkipMarker(SkipKind.intro, 0, 60000)], 2700000), isNull);
    });
  });
}
