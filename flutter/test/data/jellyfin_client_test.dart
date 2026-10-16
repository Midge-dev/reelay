import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_client.dart';
import 'package:reelay/data/jellyfin/jellyfin_image_url.dart';
import 'package:reelay/data/jellyfin/jellyfin_mappers.dart';
import 'package:reelay/data/media/artwork_url.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';

/// Answers each request from [routes], keyed "METHOD path" (no query);
/// anything unrouted fails as if nothing were listening.
class _FakeServer implements HttpClientAdapter {
  final Map<String, Object?> routes;
  final requests = <RequestOptions>[];

  _FakeServer(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final key = '${options.method} ${options.uri.path}';
    if (!routes.containsKey(key)) {
      throw DioException.connectionError(requestOptions: options, reason: 'refused');
    }
    return ResponseBody.fromString(jsonEncode(routes[key]), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _server = MediaServer(
  backend: MediaBackend.jellyfin,
  name: 'GRIM-TEST',
  baseUrl: 'http://loft:8096',
  accessToken: 'tok',
  id: 'server-1',
  userId: 'user-1',
);

(JellyfinClient, _FakeServer) _client(Map<String, Object?> routes) {
  final fake = _FakeServer(routes);
  return (JellyfinClient(_server, 'device-1', client: Dio()..httpClientAdapter = fake), fake);
}

// Trimmed from a real Jellyfin 12.1 server.
const _movie = {
  'Name': 'Big Buck Bunny',
  'Id': 'bbb',
  'Type': 'Movie',
  'DateCreated': '2008-05-27T18:46:20.0000000Z',
  'PremiereDate': '2008-04-10T00:00:00.0000000Z',
  'OfficialRating': 'G',
  'Overview': 'A day in the life of Big Buck Bunny.',
  'Genres': ['Animation', 'Comedy'],
  'CommunityRating': 6.5,
  'RunTimeTicks': 5964616670,
  'ProductionYear': 2008,
  'ProviderIds': {'Imdb': 'tt1254207', 'Tmdb': '10378', 'TmdbCollection': ''},
  'UserData': {'PlaybackPositionTicks': 1200000000, 'PlayCount': 0, 'Played': false},
  'ImageTags': {'Primary': 'p1', 'Logo': 'l1'},
  'BackdropImageTags': ['b1'],
};

const _episode = {
  'Name': 'Pilot',
  'Id': 'ep1',
  'Type': 'Episode',
  'IndexNumber': 1,
  'ParentIndexNumber': 2,
  'SeasonName': 'Season 2',
  'SeriesId': 'show1',
  'SeriesName': 'Reelay Test Show',
  'SeriesPrimaryImageTag': 'sp1',
  'ParentBackdropItemId': 'show1',
  'ParentBackdropImageTags': ['sb1'],
  'ImageTags': <String, String>{},
  'RunTimeTicks': 1800230000,
  'UserData': {'PlaybackPositionTicks': 0, 'PlayCount': 3, 'Played': true},
};

void main() {
  group('mapping', () {
    test('a movie: provider ids normalised, ticks to ms, artwork paths', () {
      final item = itemFromJson(_movie);
      expect(item.kind, MediaKind.movie);
      expect(item.externalIds, ['imdb://tt1254207', 'tmdb://10378']);
      expect(item.duration, 596461);
      expect(item.viewOffset, 120000);
      expect(item.viewCount, 0);
      expect(item.year, 2008);
      expect(item.originallyAvailableAt, '2008-04-10');
      expect(item.addedAt, DateTime.utc(2008, 5, 27, 18, 46, 20).millisecondsSinceEpoch ~/ 1000);
      expect(item.thumb, '/Items/bbb/Images/Primary?tag=p1');
      expect(item.art, '/Items/bbb/Images/Backdrop/0?tag=b1');
    });

    test('an episode without its own still borrows the show’s poster and backdrop', () {
      final item = itemFromJson(_episode);
      expect(item.kind, MediaKind.episode);
      expect(item.grandparentTitle, 'Reelay Test Show');
      expect(item.parentTitle, 'Season 2');
      expect((item.parentIndex, item.index), (2, 1));
      expect(item.thumb, '/Items/show1/Images/Primary?tag=sp1');
      expect(item.art, '/Items/show1/Images/Backdrop/0?tag=sb1');
      expect(item.viewCount, 3);
    });

    test('a detail splits people by type and reads the file’s tracks', () {
      final detail = detailFromJson({
        ..._movie,
        'Studios': [
          {'Name': 'Blender Foundation'},
        ],
        'People': [
          {'Name': 'Sacha', 'Id': 'p1', 'Role': 'Director', 'Type': 'Director'},
          {'Name': 'Sacha', 'Id': 'p1', 'Role': 'Screenplay', 'Type': 'Writer'},
          {'Name': 'Bunny', 'Id': 'p2', 'Role': 'Himself', 'Type': 'Actor', 'PrimaryImageTag': 't2'},
        ],
        'MediaSources': [
          {
            'Id': 'bbb',
            'Container': 'mov',
            'Size': 416751190,
            'RunTimeTicks': 5964616670,
            'MediaStreams': [
              {'Type': 'Video', 'Codec': 'h264', 'Index': 0, 'Width': 1280, 'Height': 720, 'RealFrameRate': 24},
              {'Type': 'Audio', 'Codec': 'aac', 'Index': 2, 'Channels': 6, 'IsDefault': true, 'Language': 'eng'},
            ],
          },
        ],
      });
      expect(detail.studio, 'Blender Foundation');
      expect(detail.directors.single.name, 'Sacha');
      expect(detail.writers.single.role, isNull, reason: 'only a cast credit names a character');
      expect(detail.roles.single.role, 'Himself');
      expect(detail.roles.single.thumb, '/Items/p2/Images/Primary?tag=t2');
      expect(detail.audienceRating, 6.5);
      final version = detail.media.single;
      expect((version.videoResolution, version.videoCodec, version.audioChannels), ('720', 'h264', 6));
      expect(version.parts.single.streams.map((s) => s.id), [0, 2]);
    });
  });

  group('client', () {
    test('libraries: only movie and show views, asked for as the signed-in user', () async {
      final (client, fake) = _client({
        'GET /UserViews': {
          'Items': [
            {'Id': 'l1', 'Name': 'Movies', 'CollectionType': 'movies'},
            {'Id': 'l2', 'Name': 'Shows', 'CollectionType': 'tvshows'},
            {'Id': 'l3', 'Name': 'Music', 'CollectionType': 'music'},
          ],
        },
      });
      final libraries = await client.fetchLibraries();
      expect(libraries.map((l) => (l.title, l.kind)), [('Movies', MediaKind.movie), ('Shows', MediaKind.show)]);
      final request = fake.requests.single;
      expect(request.queryParameters['userId'], 'user-1');
      expect(request.headers['Authorization'], contains('Token="tok"'));
      expect(request.headers['Authorization'], contains('DeviceId="device-1"'));
    });

    test('continue watching is part-watched titles then next episodes, each once', () async {
      final (client, _) = _client({
        'GET /UserItems/Resume': {
          'Items': [_movie, _episode],
        },
        'GET /Shows/NextUp': {
          'Items': [
            _episode,
            {..._episode, 'Id': 'ep2', 'IndexNumber': 2},
          ],
        },
      });
      final items = await client.fetchContinueWatching();
      expect(items.map((i) => i.id), ['bbb', 'ep1', 'ep2']);
    });

    test('recently added reads a bare list', () async {
      final (client, _) = _client({
        'GET /Items/Latest': [_movie],
      });
      expect((await client.fetchRecentlyAdded()).single.title, 'Big Buck Bunny');
    });

    test('a title gone from the server is a StateError', () async {
      final fake = _FakeServer({});
      final dio = Dio()
        ..httpClientAdapter = fake
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
                type: DioExceptionType.badResponse,
              ),
            ),
          ),
        );
      final client = JellyfinClient(_server, 'device-1', client: dio);
      expect(client.fetchDetail('gone'), throwsA(isA<StateError>()));
    });

    test('playing is a later phase, and says so', () {
      final (client, _) = _client({});
      expect(() => client.directPlayUrl(const MediaPart(id: 'x')), throwsUnsupportedError);
    });
  });

  group('artwork', () {
    test('paths join the server address; sizing asks Jellyfin to fill the box', () {
      final url = ArtworkUrl.of(_server, '/Items/bbb/Images/Primary?tag=p1')!;
      expect(url, 'http://loft:8096/Items/bbb/Images/Primary?tag=p1');
      final sized = Uri.parse(ArtworkUrl.sized(url, width: 300, height: 450));
      expect(sized.queryParameters, {'tag': 'p1', 'fillWidth': '300', 'fillHeight': '450', 'quality': '90'});
    });

    test('anything that isn’t a Jellyfin image is left to Plex’s sizing', () {
      expect(JellyfinImageUrl.isImageUrl('http://pms:32400/library/metadata/1/thumb?X-Plex-Token=t'), isFalse);
    });
  });
}
