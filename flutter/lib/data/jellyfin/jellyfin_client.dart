import 'package:dio/dio.dart';

import '../../app_version.dart';
import '../media/media_models.dart';
import '../media/media_server.dart';
import '../media/media_server_client.dart';
import 'jellyfin_auth_api.dart';
import 'jellyfin_image_url.dart';
import 'jellyfin_mappers.dart';

const _timeout = Duration(seconds: 15);

/// What list responses ask for beyond Jellyfin's defaults — enough to fill
/// a [MediaItem] (provider ids for folding, counts for shows).
const _itemFields =
    'Overview,Genres,ProviderIds,DateCreated,ChildCount,RecursiveItemCount';

/// The kinds a library grid, search or a person's credits list.
const _browsable = 'Movie,Series';

/// A Jellyfin server, spoken to as [MediaServer.userId] with that user's
/// token. Browsing only: playback lands in a later phase, and until then
/// the playback members throw [UnsupportedError].
class JellyfinClient implements MediaServerClient {
  @override
  final MediaServer server;
  final String clientIdentifier;
  final Dio _client;

  JellyfinClient(this.server, this.clientIdentifier, {Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: _timeout,
              receiveTimeout: _timeout,
              headers: const {'Accept': 'application/json'},
            ),
          );

  String get _userId => server.userId ?? '';

  Options get _headers => Options(
    headers: {
      'Authorization': jellyfinAuthorization(
        deviceId: clientIdentifier,
        deviceName: jellyfinDeviceName,
        appVersion: appVersionName,
        token: server.accessToken,
      ),
    },
  );

  Future<dynamic> _get(
    String path, [
    Map<String, Object?> query = const {},
  ]) async {
    final response = await _client.get<dynamic>(
      '${server.baseUrl}$path',
      queryParameters: {
        for (final MapEntry(:key, :value) in query.entries) key: ?value,
      },
      options: _headers,
    );
    return response.data;
  }

  /// A `{Items: [...]}` response, or a bare list (`/Items/Latest`).
  Future<List<MediaItem>> _items(
    String path, [
    Map<String, Object?> query = const {},
  ]) async {
    final data = await _get(path, {
      'userId': _userId,
      'fields': _itemFields,
      ...query,
    });
    final list = data is List
        ? data
        : (data as Map)['Items'] as List? ?? const [];
    return [for (final item in list.cast<Json>()) itemFromJson(item)];
  }

  /// Throws unless the server answers and still accepts the token — the
  /// hub's check before counting the server as connected.
  Future<void> checkSignedIn() => _get('/Users/Me');

  // ---- Browsing ----

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    final data = await _get('/UserViews', {'userId': _userId}) as Map;
    return [
      for (final view in ((data['Items'] as List?) ?? const []).cast<Json>())
        if (libraryKind(view['CollectionType'] as String?) != MediaKind.other)
          libraryFromJson(view),
    ];
  }

  @override
  Future<List<MediaItem>> fetchLibraryItems(String libraryId) =>
      _items('/Items', {
        'parentId': libraryId,
        'recursive': true,
        'includeItemTypes': _browsable,
        'sortBy': 'SortName',
      });

  /// Jellyfin keeps collections in their own view, not under a library, so
  /// there's no per-library list to show.
  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async => const [];

  @override
  Future<List<MediaItem>> fetchCollectionItems(String collectionId) =>
      _items('/Items', {'parentId': collectionId});

  @override
  Future<List<MediaItem>> fetchSeasons(String showId) =>
      _items('/Shows/$showId/Seasons');

  @override
  Future<List<MediaItem>> fetchEpisodes(String seasonId) =>
      _items('/Items', {'parentId': seasonId, 'sortBy': 'IndexNumber'});

  @override
  Future<MediaDetail> fetchDetail(String id) async {
    final Object? data;
    try {
      data = await _get('/Items/$id', {'userId': _userId});
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw StateError('This title is no longer available on the server.');
      }
      rethrow;
    }
    return detailFromJson(data as Json);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id) async {
    final similar = await _items('/Items/$id/Similar', {'limit': 12});
    return [
      if (similar.isNotEmpty)
        MediaHub(id: 'similar', title: 'More like this', items: similar),
    ];
  }

  @override
  Future<List<MediaItem>> search(String query) => _items('/Items', {
    'searchTerm': query,
    'recursive': true,
    'includeItemTypes': 'Movie,Series,Episode',
    'limit': 36,
  });

  // ---- People ----

  @override
  Future<List<MediaItem>> fetchPersonMedia(String personId) => _items(
    '/Items',
    {'personIds': personId, 'recursive': true, 'includeItemTypes': _browsable},
  );

  @override
  Future<List<Person>> searchPeople(String name) async {
    final data = await _get('/Persons', {
      'userId': _userId,
      'searchTerm': name,
      'limit': 10,
    }) as Map;
    return [
      for (final p in ((data['Items'] as List?) ?? const []).cast<Json>())
        personFromJson({
          ...p,
          'PrimaryImageTag': (p['ImageTags'] as Map?)?['Primary'],
        }),
    ];
  }

  /// Watchlist guids are Plex's own (`plex://…`), which Jellyfin can't
  /// resolve.
  @override
  Future<List<MediaItem>> findByGuid(String guid) async => const [];

  // ---- Home ----

  /// Part-watched titles first, then each show's next episode — Plex's
  /// On Deck is both.
  @override
  Future<List<MediaItem>> fetchContinueWatching() async {
    final results = await Future.wait([
      _items('/UserItems/Resume', {'mediaTypes': 'Video', 'limit': 24}),
      _items('/Shows/NextUp', {'limit': 24}),
    ]);
    final seen = <String>{};
    return [
      for (final item in results.expand((r) => r))
        if (seen.add(item.id)) item,
    ];
  }

  @override
  Future<List<MediaItem>> fetchRecentlyAdded() => _items('/Items/Latest', {
    'includeItemTypes': 'Movie,Episode',
    'limit': 24,
  });

  @override
  Future<List<MediaItem>> fetchRecentActivity() => _items('/Items', {
    'recursive': true,
    'includeItemTypes': 'Movie,Episode',
    'isPlayed': true,
    'sortBy': 'DatePlayed',
    'sortOrder': 'Descending',
    'limit': 24,
  });

  /// Jellyfin's own Suggestions mixes in folders and lone episodes; unseen
  /// films and shows in a random order suit the row better.
  @override
  Future<List<MediaItem>> fetchSuggestions() => _items('/Items', {
    'recursive': true,
    'includeItemTypes': _browsable,
    'isPlayed': false,
    'sortBy': 'Random',
    'limit': 24,
  });

  @override
  Future<MediaItem?> fetchNextEpisodeForShow(String showId) async {
    final next = await _items('/Shows/NextUp', {
      'seriesId': showId,
      'limit': 1,
    });
    if (next.isNotEmpty) return next.first;
    final first = await _items('/Shows/$showId/Episodes', {'limit': 1});
    return first.firstOrNull;
  }

  /// Jellyfin has no "hide from Continue Watching" — only clearing the
  /// progress, which is a different thing.
  @override
  Future<void> removeFromContinueWatching(String id) => throw UnsupportedError(
    'Jellyfin can’t hide a title from Continue Watching yet.',
  );

  // ---- Artwork ----

  @override
  String? imageUrl(String? path) => JellyfinImageUrl.of(server, path);

  // ---- Playback (a later phase) ----

  static UnsupportedError get _noPlayback =>
      UnsupportedError('Playing from Jellyfin arrives in a later update.');

  @override
  String directPlayUrl(MediaPart part) => throw _noPlayback;

  @override
  String transcodeUrl(
    String itemId, {
    int? subtitleStreamId,
    required int maxVideoBitrateKbps,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  }) => throw _noPlayback;

  @override
  String subtitleUrl(String key) => throw _noPlayback;

  @override
  Future<void> selectStreams(
    String partId, {
    int? audioStreamId,
    int? subtitleStreamId,
  }) async {}

  @override
  Future<void> reportProgress(
    String itemId,
    PlaybackReportState state, {
    required int timeMs,
    required int durationMs,
    required String sessionIdentifier,
  }) async {}
}
