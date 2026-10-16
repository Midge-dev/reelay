import 'package:dio/dio.dart';

import '../media/media_models.dart';
import '../media/media_server.dart';
import '../media/media_server_client.dart';
import 'plex_http_client.dart';
import 'plex_image_url.dart';
import 'plex_mappers.dart';
import 'plex_models.dart';
import 'plex_playback_urls.dart';
import 'plex_response.dart';

/// Per-library "for you" hubs to try, in priority order, when Plex has no
/// account-level "Suggested" hub enabled (requires Discover/Plex Pass).
const _suggestionHubPriority = ['suggest', 'recommend', 'topunwatched', 'startwatching', 'rediscover'];

/// Per-library "Recently Watched" hubs (movie.recentlyviewed.*, tv.recentlyviewed.*).
const _recentActivityHubPriority = ['recentlyviewed', 'recentlywatched', 'history'];

/// A Plex Media Server, spoken to over its own HTTP API. See ARCHITECTURE.md
/// §3 for the response-shape quirks this relies on.
class PlexClient implements MediaServerClient {
  @override
  final MediaServer server;
  final String clientIdentifier;
  final Dio _client = plexHttpClient();

  PlexClient(this.server, this.clientIdentifier);

  Options get _headers => Options(
    headers: {'X-Plex-Token': server.accessToken, 'X-Plex-Client-Identifier': clientIdentifier},
  );

  Future<Map<String, dynamic>> _get(String url) async {
    final response = await _client.get<Map<String, dynamic>>(url, options: _headers);
    return response.data!;
  }

  Future<List<T>> _list<T>(String path, String key, T Function(Map<String, dynamic>) fromJson) async =>
      extractMediaContainerList(await _get('${server.baseUrl}$path'), key, fromJson);

  Future<List<PlexSection>> _sections() async =>
      (await _list('/library/sections', 'Directory', PlexSection.fromJson)).where((s) => s.isBrowsable).toList();

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [for (final s in await _sections()) s.toMedia()];

  Future<List<MediaItem>> _items(String path) async => [
    for (final i in await _list(path, 'Metadata', PlexLibraryItem.fromJson)) i.toMedia(),
  ];

  Future<List<MediaItem>> _onDeckShaped(String path) async => [
    for (final i in await _list(path, 'Metadata', PlexOnDeckItem.fromJson)) i.toMedia(),
  ];

  @override
  Future<List<MediaItem>> fetchLibraryItems(String libraryId) => _items('/library/sections/$libraryId/all');

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async => [
    for (final c in await _list('/library/sections/$libraryId/collections', 'Metadata', PlexCollection.fromJson))
      c.toMedia(),
  ];

  @override
  Future<List<MediaItem>> fetchCollectionItems(String collectionId) =>
      _items('/library/metadata/$collectionId/children');

  @override
  Future<List<MediaItem>> fetchSeasons(String showId) async => [
    for (final s in await _list('/library/metadata/$showId/children', 'Metadata', PlexSeason.fromJson)) s.toMedia(),
  ];

  @override
  Future<List<MediaItem>> fetchEpisodes(String seasonId) async => [
    for (final e in await _list('/library/metadata/$seasonId/children', 'Metadata', PlexEpisode.fromJson))
      e.toMedia(),
  ];

  @override
  Future<MediaDetail> fetchDetail(String id) async {
    final items = await _list('/library/metadata/$id?includeReviews=1', 'Metadata', PlexMovieDetail.fromJson);
    if (items.isEmpty) {
      throw StateError('This title is no longer available on the server.');
    }
    return items.first.toMedia();
  }

  Future<List<PlexHub>> _hubs(String path) => _list(path, 'Hub', PlexHub.fromJson);

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id) async => [
    for (final h in await _hubs('/library/metadata/$id/related')) h.toMedia(),
  ];

  /// Plex's own hubs/search groups results by kind server-side (movie,
  /// show, episode, actor, ...); the grouping isn't used since SearchScreen
  /// regroups by kind to control its own section order and labels.
  @override
  Future<List<MediaItem>> search(String query) async => [
    for (final hub in await _hubs('/hubs/search?query=${Uri.encodeQueryComponent(query)}&limit=12'))
      for (final item in hub.items) item.toMedia(),
  ];

  /// Each item's `Role` list is only the first three names, without
  /// characters; the detail has the credit itself.
  @override
  Future<List<MediaItem>> fetchPersonMedia(String personId) => _items('/library/people/$personId/media');

  /// From search's actor hub — each with this server's tag id and Plex's
  /// global `tagKey`.
  @override
  Future<List<Person>> searchPeople(String name) async {
    final json = await _get('${server.baseUrl}/hubs/search?query=${Uri.encodeQueryComponent(name)}&limit=10');
    final hubs = (json['MediaContainer']?['Hub'] as List?) ?? const [];
    final seen = <int>{};
    return [
      for (final hub in hubs.cast<Map<String, dynamic>>())
        if (hub['type'] == 'actor')
          for (final entry in ((hub['Directory'] as List?) ?? const []).cast<Map<String, dynamic>>())
            if (entry['id'] is int && seen.add(entry['id'] as int))
              Person(
                id: '${entry['id']}',
                name: '${entry['tag'] ?? ''}',
                thumb: entry['thumb'] as String?,
                globalId: entry['tagKey'] as String?,
              ),
    ];
  }

  /// Resolves a Discover-universe guid (`plex://movie/<id>`) to this
  /// server's local library item(s), if it's in the library.
  @override
  Future<List<MediaItem>> findByGuid(String guid) => _items('/library/all?guid=${Uri.encodeQueryComponent(guid)}');

  @override
  Future<List<MediaItem>> fetchContinueWatching() => _onDeckShaped('/library/onDeck');

  @override
  Future<List<MediaItem>> fetchRecentlyAdded() => _items('/library/recentlyAdded');

  @override
  Future<List<MediaItem>> fetchSuggestions() async {
    final promoted = await _hubs('/hubs/promoted');
    final promotedHub = _firstMatchingHub(promoted, _suggestionHubPriority, fallbackToTitle: true);
    if (promotedHub != null) return [for (final i in promotedHub.items) i.toMedia()];
    return _fetchPerSectionHubItems(_suggestionHubPriority);
  }

  /// Recently finished-watching items, pulled from each library's own
  /// "Recently Watched" hub.
  @override
  Future<List<MediaItem>> fetchRecentActivity() => _fetchPerSectionHubItems(_recentActivityHubPriority);

  Future<List<MediaItem>> _fetchPerSectionHubItems(List<String> keywordPriority) async {
    final sections = await _sections();
    final results = <MediaItem>[];
    for (final section in sections) {
      List<PlexHub> sectionHubs;
      try {
        sectionHubs = await _hubs('/hubs/sections/${section.key}');
      } catch (_) {
        sectionHubs = const [];
      }
      final hub = _firstMatchingHub(sectionHubs, keywordPriority, fallbackToTitle: false);
      if (hub != null) results.addAll(hub.items.map((i) => i.toMedia()));
    }
    return results;
  }

  @override
  Future<MediaItem?> fetchNextEpisodeForShow(String showId) async {
    final embedded = await _tryEmbeddedOnDeck(showId);
    if (embedded != null) return embedded;

    final seasons = (await fetchSeasons(showId)).where((s) => (s.index ?? 0) > 0).toList();
    final firstSeason = _minByIndex(seasons, (s) => s.index);
    if (firstSeason == null) return null;

    final episodes = await fetchEpisodes(firstSeason.id);
    final firstEpisode = _minByIndex(episodes, (e) => e.index);
    if (firstEpisode == null) return null;

    return MediaItem(
      id: firstEpisode.id,
      kind: MediaKind.episode,
      title: firstEpisode.title,
      thumb: firstEpisode.thumb,
      parentIndex: firstSeason.index,
      index: firstEpisode.index,
    );
  }

  /// The show's own metadata response can embed `OnDeck.Metadata[0]`
  /// directly — a shape distinct enough from the other list endpoints that
  /// it's parsed inline rather than through [extractMediaContainerList].
  Future<MediaItem?> _tryEmbeddedOnDeck(String showId) async {
    try {
      final json = await _get('${server.baseUrl}/library/metadata/$showId?includeOnDeck=1');
      final items = extractMediaContainer(json)?['Metadata'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;
      final onDeck = (items.first as Map<String, dynamic>)['OnDeck'] as Map<String, dynamic>?;
      final onDeckItems = onDeck?['Metadata'] as List<dynamic>?;
      if (onDeckItems == null || onDeckItems.isEmpty) return null;
      return PlexOnDeckItem.fromJson(onDeckItems.first as Map<String, dynamic>).toMedia();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removeFromContinueWatching(String id) async {
    await _client.put<void>('${server.baseUrl}/actions/removeFromContinueWatching?ratingKey=$id', options: _headers);
  }

  @override
  String? imageUrl(String? path) => PlexImageUrl.of(server, path);

  @override
  String directPlayUrl(MediaPart part) => plexDirectPlayUrl(server, part);

  @override
  String transcodeUrl(
    String itemId, {
    String? partId,
    int? subtitleStreamId,
    int? audioStreamId,
    required int maxVideoBitrateKbps,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  }) => plexTranscodeUrl(
    server,
    itemId,
    subtitleStreamId: subtitleStreamId,
    maxVideoBitrateKbps: maxVideoBitrateKbps,
    clientIdentifier: clientIdentifier,
    sessionIdentifier: sessionIdentifier,
    sessionId: sessionId,
    offsetMs: offsetMs,
  );

  @override
  bool get transcodeStartsAtOffset => true;

  @override
  String subtitleUrl(String key) => '${server.baseUrl}$key?X-Plex-Token=${server.accessToken}';

  /// See [streamSelectionUrl].
  @override
  Future<void> selectStreams(String partId, {int? audioStreamId, int? subtitleStreamId}) async {
    if (audioStreamId == null && subtitleStreamId == null) return;
    await _client.put<void>(
      streamSelectionUrl(server, partId, audioStreamId: audioStreamId, subtitleStreamId: subtitleStreamId),
      options: _headers,
    );
  }

  @override
  Future<void> reportProgress(
    String itemId,
    PlaybackReportState state, {
    required int timeMs,
    required int durationMs,
    required String sessionIdentifier,
  }) async {
    try {
      await _client.get<void>(
        timelineReportUrl(server, itemId, state.name, timeMs, durationMs),
        options: Options(headers: timelineReportHeaders(server, clientIdentifier, sessionIdentifier)),
      );
    } catch (_) {
      // Fire-and-forget: a missed progress report isn't worth surfacing.
    }
  }

  /// The item with the lowest index (missing indexes last) — a stable
  /// single-pass min, unlike a full `List.sort` (Dart's sort isn't
  /// guaranteed stable, which could pick a different element on ties).
  T? _minByIndex<T>(List<T> items, int? Function(T) indexOf) {
    T? best;
    var bestIndex = 1 << 30;
    for (final item in items) {
      final index = indexOf(item) ?? (1 << 30);
      if (best == null || index < bestIndex) {
        best = item;
        bestIndex = index;
      }
    }
    return best;
  }

  PlexHub? _firstMatchingHub(List<PlexHub> hubs, List<String> keywordPriority, {required bool fallbackToTitle}) {
    for (final keyword in keywordPriority) {
      for (final hub in hubs) {
        if (hub.items.isEmpty) continue;
        final haystack = hub.hubIdentifier?.toLowerCase() ?? (fallbackToTitle ? hub.title.toLowerCase() : '');
        if (haystack.contains(keyword)) return hub;
      }
    }
    return null;
  }
}
