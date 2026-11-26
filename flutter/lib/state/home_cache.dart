import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/media/media_models.dart';
import '../data/media/media_server.dart';
import '../data/plex/secure_token_store.dart';
import 'app_state.dart';
import 'duplicate_fold.dart';

/// What Home showed last time, for one profile: its rows and the
/// watchlist, saved as they were so the next launch can show them at once
/// while the servers are asked what has changed.
class SavedHome {
  final Home home;
  final List<MediaItem>? plexWatchlist;
  final List<MediaItem> jellyfinFavorites;
  final Map<String, List<String>> watchlistEntryIds;
  final Map<String, String?> watchlistAvailability;

  const SavedHome({
    required this.home,
    this.plexWatchlist,
    this.jellyfinFavorites = const [],
    this.watchlistEntryIds = const {},
    this.watchlistAvailability = const {},
  });
}

/// Saves the last Home per profile. The rows go in plain preferences with
/// every server's token taken out; the tokens go in the secure store, as
/// every other token does. A save that can't be read back (an older
/// format, a token gone) is no saved Home at all.
class HomeCache {
  HomeCache(this._prefs, this._tokens);

  final SharedPreferencesAsync _prefs;
  final SecureTokenStore _tokens;

  /// Bumped whenever the saved shape changes; older saves are ignored.
  static const _version = 1;

  static String _key(String profileId) => 'home_cache_$profileId';

  Future<SavedHome?> load(String profileId) async {
    try {
      final text = await _prefs.getString(_key(profileId));
      final tokensText = await _tokens.loadHomeServerTokens(profileId);
      if (text == null || tokensText == null) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['v'] != _version) return null;
      final tokens = (jsonDecode(tokensText) as Map<String, dynamic>).cast<String, String>();
      return _decode(json, tokens);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String profileId, SavedHome saved) async {
    final servers = {for (final cs in saved.home.servers) cs.server.id: cs.server};
    final tokens = {for (final s in servers.values) s.id: s.accessToken};
    await _tokens.saveHomeServerTokens(profileId, jsonEncode(tokens));
    await _prefs.setString(_key(profileId), jsonEncode(_encode(saved, servers.values)));
  }

  Future<void> clear(String profileId) async {
    await _prefs.remove(_key(profileId));
    await _tokens.clearHomeServerTokens(profileId);
  }

  // ---- Encoding ----

  static Map<String, Object?> _encode(SavedHome s, Iterable<MediaServer> servers) {
    final home = s.home;
    List<Object?> works(List<FoldedWork<MediaItem>> list) => [
      for (final w in list)
        {
          'guid': w.guid,
          'copies': [
            for (final c in w.copies) {'server': c.server.id, 'reach': c.reachability.name, 'item': _item(c.value)},
          ],
        },
    ];
    return {
      'v': _version,
      'servers': [for (final server in servers) _server(server)],
      'reach': {for (final cs in home.servers) cs.server.id: cs.reachability.name},
      'order': [for (final cs in home.servers) cs.server.id],
      'sections': [
        for (final g in home.sectionGroups)
          {
            'kind': g.kind.name,
            'title': g.title,
            'by': {
              for (final e in g.sectionsByServerId.entries)
                e.key: {'id': e.value.id, 'title': e.value.title, 'kind': e.value.kind.name},
            },
          },
      ],
      'onDeck': works(home.onDeck),
      'recentlyAdded': works(home.recentlyAdded),
      'recentActivity': works(home.recentActivity),
      'suggestions': works(home.suggestions),
      'plexWatchlist': s.plexWatchlist?.map(_item).toList(),
      'jellyfinFavorites': s.jellyfinFavorites.map(_item).toList(),
      'watchlistEntryIds': s.watchlistEntryIds,
      'watchlistAvailability': s.watchlistAvailability,
    };
  }

  static SavedHome _decode(Map<String, dynamic> json, Map<String, String> tokens) {
    final servers = <String, MediaServer>{
      for (final s in (json['servers'] as List).cast<Map<String, dynamic>>())
        s['id'] as String: _serverFrom(s, tokens[s['id']] ?? (throw const FormatException('token gone'))),
    };
    final reach = (json['reach'] as Map<String, dynamic>).cast<String, String>();
    ServerReachability reachOf(String name) => ServerReachability.values.byName(name);
    List<FoldedWork<MediaItem>> works(Object? list) => [
      for (final w in (list as List).cast<Map<String, dynamic>>())
        FoldedWork(w['guid'] as String?, [
          for (final c in (w['copies'] as List).cast<Map<String, dynamic>>())
            Sourced(
              _itemFrom(c['item'] as Map<String, dynamic>),
              servers[c['server']] ?? (throw const FormatException('server gone')),
              reachOf(c['reach'] as String),
            ),
        ]),
    ];
    List<MediaItem> items(Object? list) => [for (final i in (list as List).cast<Map<String, dynamic>>()) _itemFrom(i)];
    return SavedHome(
      home: Home(
        servers: [
          for (final id in (json['order'] as List).cast<String>()) ReachableServer(servers[id]!, reachOf(reach[id]!)),
        ],
        sectionGroups: [
          for (final g in (json['sections'] as List).cast<Map<String, dynamic>>())
            SectionGroup(
              kind: MediaKind.values.byName(g['kind'] as String),
              title: g['title'] as String,
              sectionsByServerId: {
                for (final e in (g['by'] as Map<String, dynamic>).entries)
                  e.key: MediaLibrary(
                    id: e.value['id'] as String,
                    title: e.value['title'] as String,
                    kind: MediaKind.values.byName(e.value['kind'] as String),
                  ),
              },
            ),
        ],
        onDeck: works(json['onDeck']),
        recentlyAdded: works(json['recentlyAdded']),
        recentActivity: works(json['recentActivity']),
        suggestions: works(json['suggestions']),
      ),
      plexWatchlist: json['plexWatchlist'] == null ? null : items(json['plexWatchlist']),
      jellyfinFavorites: items(json['jellyfinFavorites']),
      watchlistEntryIds: {
        for (final e in (json['watchlistEntryIds'] as Map<String, dynamic>).entries)
          e.key: (e.value as List).cast<String>(),
      },
      watchlistAvailability: (json['watchlistAvailability'] as Map<String, dynamic>).cast<String, String?>(),
    );
  }

  /// No token: that's kept in the secure store, by server id.
  static Map<String, Object?> _server(MediaServer s) => {
    'backend': s.backend.name,
    'name': s.name,
    'baseUrl': s.baseUrl,
    'id': s.id,
    'userId': s.userId,
    'clientId': s.clientId,
  };

  static MediaServer _serverFrom(Map<String, dynamic> j, String token) => MediaServer(
    backend: MediaBackend.values.byName(j['backend'] as String),
    name: j['name'] as String,
    baseUrl: j['baseUrl'] as String,
    accessToken: token,
    id: j['id'] as String,
    userId: j['userId'] as String?,
    clientId: j['clientId'] as String?,
  );

  static Map<String, Object?> _item(MediaItem i) => {
    'id': i.id,
    'kind': i.kind.name,
    'title': i.title,
    'parentTitle': i.parentTitle,
    'parentId': i.parentId,
    'grandparentTitle': i.grandparentTitle,
    'parentIndex': i.parentIndex,
    'index': i.index,
    'year': i.year,
    'thumb': i.thumb,
    'art': i.art,
    'summary': i.summary,
    'addedAt': i.addedAt,
    'originallyAvailableAt': i.originallyAvailableAt,
    'contentRating': i.contentRating,
    'guid': i.guid,
    'externalIds': i.externalIds,
    'leafCount': i.leafCount,
    'childCount': i.childCount,
    'genres': i.genres,
    'collections': i.collections,
    'duration': i.duration,
    'viewOffset': i.viewOffset,
    'lastViewedAt': i.lastViewedAt,
    'viewCount': i.viewCount,
  }..removeWhere((_, v) => v == null || (v is List && v.isEmpty));

  static MediaItem _itemFrom(Map<String, dynamic> j) {
    List<String> strings(String key) => (j[key] as List?)?.cast<String>() ?? const [];
    return MediaItem(
      id: j['id'] as String,
      kind: MediaKind.values.byName(j['kind'] as String),
      title: j['title'] as String,
      parentTitle: j['parentTitle'] as String?,
      parentId: j['parentId'] as String?,
      grandparentTitle: j['grandparentTitle'] as String?,
      parentIndex: j['parentIndex'] as int?,
      index: j['index'] as int?,
      year: j['year'] as int?,
      thumb: j['thumb'] as String?,
      art: j['art'] as String?,
      summary: j['summary'] as String?,
      addedAt: j['addedAt'] as int?,
      originallyAvailableAt: j['originallyAvailableAt'] as String?,
      contentRating: j['contentRating'] as String?,
      guid: j['guid'] as String?,
      externalIds: strings('externalIds'),
      leafCount: j['leafCount'] as int?,
      childCount: j['childCount'] as int?,
      genres: strings('genres'),
      collections: strings('collections'),
      duration: j['duration'] as int?,
      viewOffset: j['viewOffset'] as int?,
      lastViewedAt: j['lastViewedAt'] as int?,
      viewCount: j['viewCount'] as int?,
    );
  }
}
