import 'package:dio/dio.dart';

import 'plex_http_client.dart';
import 'plex_models.dart';
import 'plex_response.dart';

/// Per-library "for you" hubs to try, in priority order, when Plex has no
/// account-level "Suggested" hub enabled (requires Discover/Plex Pass).
const _suggestionHubPriority = ['suggest', 'recommend', 'topunwatched', 'startwatching', 'rediscover'];

/// Per-library "Recently Watched" hubs (movie.recentlyviewed.*, tv.recentlyviewed.*).
const _recentActivityHubPriority = ['recentlyviewed', 'recentlywatched', 'history'];

/// PUT this before opening a burn-in transcode: PMS's transcoder burns
/// whichever subtitle the part has *selected* on the server and ignores the
/// transcode URL's subtitleStreamID (seen against a real PMS — see plezy's
/// `selectSubtitleStreamForBurn`). Plex Web does the same PUT, so it also
/// becomes the remembered choice for next time.
String subtitleSelectionUrl(PlexServer server, int partId, int subtitleStreamId) =>
    '${server.baseUrl}/library/parts/$partId?subtitleStreamID=$subtitleStreamId&allParts=1';

class PlexServerApi {
  final PlexServer server;
  final String clientIdentifier;
  final Dio _client = plexHttpClient();

  PlexServerApi(this.server, this.clientIdentifier);

  Options get _headers => Options(headers: {
        'X-Plex-Token': server.accessToken,
        'X-Plex-Client-Identifier': clientIdentifier,
      });

  Future<Map<String, dynamic>> _get(String url) async {
    final response = await _client.get<Map<String, dynamic>>(url, options: _headers);
    return response.data!;
  }

  Future<List<PlexSection>> fetchSections() async {
    final json = await _get('${server.baseUrl}/library/sections');
    final all = extractMediaContainerList(json, 'Directory', PlexSection.fromJson);
    return all.where((s) => s.isBrowsable).toList();
  }

  Future<List<PlexLibraryItem>> fetchLibraryItems(String sectionKey) async {
    final json = await _get('${server.baseUrl}/library/sections/$sectionKey/all');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  Future<List<PlexCollection>> fetchCollections(String sectionKey) async {
    final json = await _get('${server.baseUrl}/library/sections/$sectionKey/collections');
    return extractMediaContainerList(json, 'Metadata', PlexCollection.fromJson);
  }

  Future<List<PlexLibraryItem>> fetchCollectionItems(String collectionRatingKey) async {
    final json = await _get('${server.baseUrl}/library/metadata/$collectionRatingKey/children');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  Future<List<PlexSeason>> fetchSeasons(String showRatingKey) async {
    final json = await _get('${server.baseUrl}/library/metadata/$showRatingKey/children');
    return extractMediaContainerList(json, 'Metadata', PlexSeason.fromJson);
  }

  Future<List<PlexEpisode>> fetchEpisodes(String seasonRatingKey) async {
    final json = await _get('${server.baseUrl}/library/metadata/$seasonRatingKey/children');
    return extractMediaContainerList(json, 'Metadata', PlexEpisode.fromJson);
  }

  Future<PlexMovieDetail> fetchMovieDetail(String ratingKey) async {
    final json = await _get('${server.baseUrl}/library/metadata/$ratingKey?includeReviews=1');
    final items = extractMediaContainerList(json, 'Metadata', PlexMovieDetail.fromJson);
    if (items.isEmpty) {
      throw StateError('This title is no longer available on the server.');
    }
    return items.first;
  }

  Future<List<PlexHub>> fetchRelatedHubs(String ratingKey) async {
    final json = await _get('${server.baseUrl}/library/metadata/$ratingKey/related');
    return extractMediaContainerList(json, 'Hub', PlexHub.fromJson);
  }

  /// Global search (screen 05) — Plex's own hubs/search groups results by
  /// kind server-side (movie, show, episode, actor, ...); the hub grouping
  /// itself isn't used here since SearchScreen regroups by [PlexOnDeckItem
  /// .type] to control its own SERIES/MOVIES section order and labels.
  Future<List<PlexOnDeckItem>> search(String query) async {
    final json = await _get('${server.baseUrl}/hubs/search?query=${Uri.encodeQueryComponent(query)}&limit=12');
    final hubs = extractMediaContainerList(json, 'Hub', PlexHub.fromJson);
    return hubs.expand((hub) => hub.items).toList();
  }

  /// Everything [personId] (this server's tag id) is credited on, across
  /// every section — acting, directing or writing. Each item's `Role` list
  /// is only the first three names, without characters; the detail has
  /// the credit itself.
  Future<List<PlexLibraryItem>> fetchPersonMedia(int personId) async {
    final json = await _get('${server.baseUrl}/library/people/$personId/media');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  /// People matching [name] on this server, from search's actor hub —
  /// each with this server's tag id and Plex's global `tagKey`, which is
  /// how the same person is recognised on another server.
  Future<List<PlexPerson>> searchPeople(String name) async {
    final json = await _get('${server.baseUrl}/hubs/search?query=${Uri.encodeQueryComponent(name)}&limit=10');
    final hubs = (json['MediaContainer']?['Hub'] as List?) ?? const [];
    final seen = <int>{};
    return [
      for (final hub in hubs.cast<Map<String, dynamic>>())
        if (hub['type'] == 'actor')
          for (final entry in ((hub['Directory'] as List?) ?? const []).cast<Map<String, dynamic>>())
            if (entry['id'] is int && seen.add(entry['id'] as int))
              PlexPerson(
                id: entry['id'] as int,
                tag: '${entry['tag'] ?? ''}',
                thumb: entry['thumb'] as String?,
                tagKey: entry['tagKey'] as String?,
              ),
    ];
  }

  Future<List<PlexLibraryItem>> fetchLibraryItemsByActor(String sectionKey, int actorId) async {
    final json = await _get('${server.baseUrl}/library/sections/$sectionKey/all?actor=$actorId');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  /// Resolves a Discover-universe guid (`plex://movie/<id>`) to this
  /// server's local library item(s), if it's in the library.
  Future<List<PlexLibraryItem>> fetchLibraryItemsByGuid(String guid) async {
    final json = await _get('${server.baseUrl}/library/all?guid=${Uri.encodeQueryComponent(guid)}');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  Future<List<PlexOnDeckItem>> fetchOnDeck() async {
    final json = await _get('${server.baseUrl}/library/onDeck');
    return extractMediaContainerList(json, 'Metadata', PlexOnDeckItem.fromJson);
  }

  Future<PlexOnDeckItem?> fetchNextEpisodeForShow(String showRatingKey) async {
    final embedded = await _tryEmbeddedOnDeck(showRatingKey);
    if (embedded != null) return embedded;

    final seasons = (await fetchSeasons(showRatingKey)).where((s) => (s.index ?? 0) > 0).toList();
    final firstSeason = _minByIndex(seasons, (s) => s.index);
    if (firstSeason == null) return null;

    final episodes = await fetchEpisodes(firstSeason.ratingKey);
    final firstEpisode = _minByIndex(episodes, (e) => e.index);
    if (firstEpisode == null) return null;

    return PlexOnDeckItem(
      ratingKey: firstEpisode.ratingKey,
      type: 'episode',
      title: firstEpisode.title,
      thumb: firstEpisode.thumb,
      parentIndex: firstSeason.index,
      index: firstEpisode.index,
    );
  }

  /// The show's own metadata response can embed `OnDeck.Metadata[0]`
  /// directly — a shape distinct enough from the other list endpoints that
  /// it's parsed inline rather than through [extractMediaContainerList].
  Future<PlexOnDeckItem?> _tryEmbeddedOnDeck(String showRatingKey) async {
    try {
      final json = await _get('${server.baseUrl}/library/metadata/$showRatingKey?includeOnDeck=1');
      final items = extractMediaContainer(json)?['Metadata'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;
      final onDeck = (items.first as Map<String, dynamic>)['OnDeck'] as Map<String, dynamic>?;
      final onDeckItems = onDeck?['Metadata'] as List<dynamic>?;
      if (onDeckItems == null || onDeckItems.isEmpty) return null;
      return PlexOnDeckItem.fromJson(onDeckItems.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> removeFromContinueWatching(String ratingKey) async {
    await _client.put<void>('${server.baseUrl}/actions/removeFromContinueWatching?ratingKey=$ratingKey', options: _headers);
  }

  /// See [subtitleSelectionUrl].
  Future<void> selectSubtitleStream(int partId, int subtitleStreamId) async {
    await _client.put<void>(subtitleSelectionUrl(server, partId, subtitleStreamId), options: _headers);
  }

  Future<List<PlexLibraryItem>> fetchRecentlyAdded() async {
    final json = await _get('${server.baseUrl}/library/recentlyAdded');
    return extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
  }

  Future<List<PlexOnDeckItem>> fetchSuggestions() async {
    final json = await _get('${server.baseUrl}/hubs/promoted');
    final promoted = extractMediaContainerList(json, 'Hub', PlexHub.fromJson);
    final promotedHub = _firstMatchingHub(promoted, _suggestionHubPriority, fallbackToTitle: true);
    if (promotedHub != null) return promotedHub.items;
    return _fetchPerSectionHubItems(_suggestionHubPriority);
  }

  /// Recently finished-watching items, pulled from each library's own
  /// "Recently Watched" hub.
  Future<List<PlexOnDeckItem>> fetchRecentActivity() => _fetchPerSectionHubItems(_recentActivityHubPriority);

  Future<List<PlexOnDeckItem>> _fetchPerSectionHubItems(List<String> keywordPriority) async {
    final sections = await fetchSections();
    final results = <PlexOnDeckItem>[];
    for (final section in sections) {
      List<PlexHub> sectionHubs;
      try {
        final json = await _get('${server.baseUrl}/hubs/sections/${section.key}');
        sectionHubs = extractMediaContainerList(json, 'Hub', PlexHub.fromJson);
      } catch (_) {
        sectionHubs = const [];
      }
      final hub = _firstMatchingHub(sectionHubs, keywordPriority, fallbackToTitle: false);
      if (hub != null) results.addAll(hub.items);
    }
    return results;
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
