import 'dart:convert';

import 'fake_http.dart';

/// One playback report the app sent: start, progress or stopped.
class PlaybackReport {
  PlaybackReport(this.kind, this.itemId, this.positionMs);
  final String kind; // 'start', 'progress', 'stopped'
  final String itemId;
  final int positionMs;

  @override
  String toString() => '$kind $itemId @${positionMs ~/ 1000}s';
}

/// A small Jellyfin server — two libraries, eight films, two shows — that
/// answers what JellyfinClient asks, shaped like a real 12.x server
/// (see test/data/jellyfin_client_test.dart for the trimmed originals).
///
/// Journeys read it to know what should be on screen: [movies] in
/// library order, [shows], and what each home row holds.
class FakeJellyfin {
  FakeJellyfin({this.baseUrl = 'http://den.local:8096', this.unfindable = const {}, this.extraFilms = 0});

  /// More films after the usual eight ("Film 09", "Film 10", …) — a library
  /// big enough for its grid to scroll.
  final int extraFilms;

  final String baseUrl;

  /// Ids still listed (on the watchlist, say) that a lookup by id no longer
  /// finds — a title removed from the server since.
  final Set<String> unfindable;
  static const userId = 'u1';

  /// A second account on the same server — riley / jumanji — that sees
  /// only Movies, as a restricted Jellyfin user does: profile journeys
  /// check each profile gets its own account's hub.
  static const rileyUserId = 'u2';
  static const rileyToken = 'jf-token-riley';
  bool _asRiley(FakeRequest r) =>
      r.headers.values.any((v) => v.contains(rileyToken)) || r.uri.queryParameters.values.any((v) => v == rileyToken);
  static const serverId = 'jf-den';

  static const movieTitles = ['Arrival', 'Blade Runner', 'Contact', 'Dune', 'Ex Machina', 'Gattaca', 'Her', 'Interstellar'];

  late final List<Map<String, Object?>> movies = [
    for (var i = 0; i < movieTitles.length; i++) _movie('m${i + 1}', movieTitles[i], 1980 + i * 5),
    for (var i = movieTitles.length; i < movieTitles.length + extraFilms; i++)
      _movie('m${i + 1}', 'Film ${(i + 1).toString().padLeft(2, '0')}', 1960 + i),
  ];

  late final List<Map<String, Object?>> shows = [
    _show('s1', 'Severance', seasons: 2, episodesPerSeason: 4),
    _show('s2', 'Andor', seasons: 1, episodesPerSeason: 3),
  ];

  /// Collections (BoxSets). Jellyfin keeps them in a view of their own
  /// (CollectionType "boxsets"), not under the library their titles are in.
  static const collectionsViewId = 'l9';
  late final collections = <Map<String, Object?>>[
    {'Name': 'Sci-fi favourites', 'Id': 'c1', 'Type': 'BoxSet', 'ServerId': serverId, 'ChildCount': 3, 'ImageTags': <String, String>{}},
    {'Name': 'Eighties', 'Id': 'c2', 'Type': 'BoxSet', 'ServerId': serverId, 'ChildCount': 2, 'ImageTags': <String, String>{}},
  ];
  static const collectionMembers = {
    'c1': ['m1', 'm5', 'm8'],
    'c2': ['m1', 'm2'],
  };

  final _seasons = <String, List<Map<String, Object?>>>{};
  final _episodes = <String, List<Map<String, Object?>>>{};

  /// Part-watched (Continue Watching), favourited (the watchlist), played.
  final resumeIds = {'m2'};
  final favoriteIds = {'m3', 's2'};
  final playedIds = {'m4'};

  /// Media segments (Jellyfin 10.10+, from a plugin like Intro Skipper),
  /// by episode. Severance's have an intro, 1:00–2:30, and end credits
  /// over the last five minutes of the fake player's 100-minute files;
  /// Andor's have none, so it shows how a server without them plays.
  static const introStartMs = 60000, introEndMs = 150000, creditsStartMs = 95 * 60000;
  late final segments = <String, List<Map<String, Object?>>>{
    for (final e in _allEpisodes)
      if (e['SeriesId'] == 's1')
        e['Id']! as String: [
          {'Type': 'Intro', 'StartTicks': introStartMs * 10000, 'EndTicks': introEndMs * 10000},
          {'Type': 'Outro', 'StartTicks': creditsStartMs * 10000, 'EndTicks': 100 * 60000 * 10000},
        ],
  };

  /// The episode Next Up offers, as (season, episode); Jellyfin works it
  /// out from the last one played.
  var nextUpEpisode = (1, 2);

  /// What playback reported, in order.
  final playbackReports = <PlaybackReport>[];

  /// Saved positions, in ticks, as playback last reported them; a title in
  /// [resumeIds] with none here is a third of the way in.
  final positions = <String, int>{};

  Map<String, Object?> _userData(String id, {int? runTicks}) => {
    'PlaybackPositionTicks': resumeIds.contains(id) && runTicks != null ? positions[id] ?? runTicks ~/ 3 : 0,
    'PlayCount': playedIds.contains(id) ? 1 : 0,
    'Played': playedIds.contains(id),
    'IsFavorite': favoriteIds.contains(id),
    if (resumeIds.contains(id)) 'LastPlayedDate': '2026-11-17T20:00:00.0000000Z',
  };

  Map<String, Object?> _movie(String id, String name, int year) {
    const ticks = 60000000000; // 100 minutes, as long as the fake player's files
    return {
      'Name': name,
      'Id': id,
      'Type': 'Movie',
      'ServerId': serverId,
      'ProductionYear': year,
      'PremiereDate': '$year-06-01T00:00:00.0000000Z',
      'DateCreated': '2026-01-0${(id.hashCode % 9) + 1}T00:00:00.0000000Z',
      'OfficialRating': 'PG-13',
      'Overview': '$name, a film.',
      'Genres': ['Science Fiction'],
      'CommunityRating': 7.5,
      'RunTimeTicks': ticks,
      'ProviderIds': {'Imdb': 'tt00$id'},
      'UserData': _userData(id, runTicks: ticks),
      'ImageTags': {'Primary': 'p-$id'},
      'BackdropImageTags': ['b-$id'],
    };
  }

  Map<String, Object?> _show(String id, String name, {required int seasons, required int episodesPerSeason}) {
    final seasonList = <Map<String, Object?>>[];
    for (var s = 1; s <= seasons; s++) {
      final seasonId = '$id-s$s';
      seasonList.add({
        'Name': 'Season $s',
        'Id': seasonId,
        'Type': 'Season',
        'ServerId': serverId,
        'IndexNumber': s,
        'SeriesId': id,
        'SeriesName': name,
        'ImageTags': {'Primary': 'p-$seasonId'},
        'UserData': _userData(seasonId),
      });
      _episodes[seasonId] = [
        for (var e = 1; e <= episodesPerSeason; e++)
          {
            'Name': '$name ${s}x$e',
            'Id': '$seasonId-e$e',
            'Type': 'Episode',
            'ServerId': serverId,
            'IndexNumber': e,
            'ParentIndexNumber': s,
            'SeasonId': seasonId,
            'SeasonName': 'Season $s',
            'SeriesId': id,
            'SeriesName': name,
            'SeriesPrimaryImageTag': 'p-$id',
            'ImageTags': <String, String>{},
            'RunTimeTicks': 30000000000,
            // Real servers carry an episode's own TVDB id, which is what
            // folds it with the Plex copy of the same episode.
            'ProviderIds': {'Tvdb': '9${id}0${s}0$e'},
            'UserData': _userData('$seasonId-e$e'),
          },
      ];
    }
    _seasons[id] = seasonList;
    return {
      'Name': name,
      'Id': id,
      'Type': 'Series',
      'ServerId': serverId,
      'ProductionYear': 2022,
      'Overview': '$name, a show.',
      'Genres': ['Drama'],
      'ChildCount': seasons,
      'ProviderIds': {'Tvdb': '9$id'},
      'UserData': _userData(id),
      'ImageTags': {'Primary': 'p-$id'},
      'BackdropImageTags': ['b-$id'],
    };
  }

  /// Episodes are built with their show — reading [shows] first, or a
  /// request that comes before anything else (Next Up, at start-up) finds
  /// none.
  Iterable<Map<String, Object?>> get _allEpisodes {
    shows;
    return _episodes.values.expand((e) => e);
  }

  Map<String, Object?>? _byId(String id) {
    for (final item in [...movies, ...shows, ...collections, ..._seasons.values.expand((s) => s), ..._allEpisodes]) {
      if (item['Id'] == id) return item;
    }
    return null;
  }

  Map<String, Object?> _detail(Map<String, Object?> item) => {
    ..._fresh(item),
    if (item['Type'] == 'Movie' || item['Type'] == 'Episode')
      'MediaSources': [
        {
          'Id': item['Id'],
          'Container': 'mkv',
          'Size': 4000000000,
          'RunTimeTicks': item['RunTimeTicks'],
          'Path': '/media/${item['Id']}.mkv',
          'MediaStreams': [
            {'Type': 'Video', 'Codec': 'h264', 'Index': 0, 'Width': 1920, 'Height': 1080, 'RealFrameRate': 23.976},
            {'Type': 'Audio', 'Codec': 'eac3', 'Index': 1, 'Channels': 6, 'IsDefault': true, 'Language': 'eng', 'LocalizedLanguage': 'English', 'DisplayTitle': 'English - Dolby Digital+ - 5.1'},
            {'Type': 'Subtitle', 'Codec': 'subrip', 'Index': 2, 'Language': 'eng', 'LocalizedLanguage': 'English', 'DisplayTitle': 'English', 'IsExternal': true, 'IsTextSubtitleStream': true, 'DeliveryUrl': '/Videos/${item['Id']}/${item['Id']}/Subtitles/2/0/Stream.vtt'},
          ],
        },
      ],
    // A full cast, as a real title has: enough to scroll the Cast & crew row.
    'People': [
      {'Name': 'Ada Director', 'Id': 'pd', 'Type': 'Director'},
      {'Name': 'Lee Lead', 'Id': 'pa', 'Role': 'The lead', 'Type': 'Actor'},
      for (var i = 1; i <= 10; i++) {'Name': 'Cast Member $i', 'Id': 'pc$i', 'Role': 'Role $i', 'Type': 'Actor'},
    ],
    'Studios': [
      {'Name': 'Fake Studio'},
    ],
  };

  /// An item as served now: its UserData read afresh, so what playback
  /// reported shows up on the next fetch, as on a real server.
  Map<String, Object?> _fresh(Map<String, Object?> item) => {
    ...item,
    'UserData': _userData(item['Id']! as String, runTicks: item['RunTimeTicks'] as int?),
  };

  Map<String, Object?> _items(Iterable<Map<String, Object?>> items) {
    final list = items.map(_fresh).toList();
    return {'Items': list, 'TotalRecordCount': list.length};
  }

  /// The route to hand FakeNetwork.
  FakeReply? route(FakeRequest r) {
    final base = Uri.parse(baseUrl);
    if (r.uri.host != base.host || r.uri.port != base.port) return null;
    final path = r.uri.path;
    final q = r.uri.queryParameters;

    if (path.contains('/Images/')) return FakeReply.bytes(transparentPng, contentType: 'image/png');
    if (path.startsWith('/Sessions/Playing')) {
      final body = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
      final id = body['ItemId'] as String;
      final ticks = (body['PositionTicks'] as num?)?.toInt() ?? 0;
      final kind = path.endsWith('/Stopped') ? 'stopped' : (path.endsWith('/Progress') ? 'progress' : 'start');
      playbackReports.add(PlaybackReport(kind, id, ticks ~/ 10000));
      // As Jellyfin keeps it: stopping saves the spot, or — past 90% —
      // marks the title played and drops it from Resume.
      if (kind == 'stopped') {
        final run = (_byId(id)?['RunTimeTicks'] as int?) ?? 0;
        if (run > 0 && ticks >= run * 0.9) {
          resumeIds.remove(id);
          positions.remove(id);
          playedIds.add(id);
        } else if (ticks > 0) {
          resumeIds.add(id);
          positions[id] = ticks;
        }
      }
      return FakeReply.empty();
    }
    final userData = RegExp(r'^/UserItems/([^/]+)/UserData$').firstMatch(path);
    if (r.method == 'POST' && userData != null) {
      resumeIds.remove(userData[1]);
      positions.remove(userData[1]);
      return FakeReply.json({});
    }
    // Signing in (setup's typed path): sam / popcorn, or riley / jumanji.
    if (r.method == 'POST' && path == '/Users/AuthenticateByName') {
      final body = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
      if (body['Username'] == 'riley' && body['Pw'] == 'jumanji') {
        return FakeReply.json({
          'User': {'Id': rileyUserId, 'Name': 'riley', 'ServerId': serverId},
          'AccessToken': rileyToken,
          'ServerId': serverId,
        });
      }
      if (body['Username'] != 'sam' || body['Pw'] != 'popcorn') return FakeReply.json({}, status: 401);
      return FakeReply.json({
        'User': {'Id': userId, 'Name': 'sam', 'ServerId': serverId},
        'AccessToken': 'jf-token',
        'ServerId': serverId,
      });
    }
    if (r.method == 'POST' || r.method == 'DELETE') {
      final fav = RegExp(r'^/UserFavoriteItems/(.+)$').firstMatch(path);
      if (fav != null) r.method == 'POST' ? favoriteIds.add(fav[1]!) : favoriteIds.remove(fav[1]!);
      return FakeReply.json({});
    }

    switch (path) {
      case '/System/Info/Public':
        // As a real server answers: setup checks it's Jellyfin by ProductName.
        return FakeReply.json({'ServerName': 'Den', 'Id': 'jf-den', 'Version': '12.1.0', 'ProductName': 'Jellyfin Server', 'StartupWizardCompleted': true});
      case '/Users/Me':
        return FakeReply.json(_asRiley(r) ? {'Id': rileyUserId, 'Name': 'riley'} : {'Id': userId, 'Name': 'sam'});
      case '/UserViews':
        return FakeReply.json(_items([
          {'Id': 'l1', 'Name': 'Movies', 'CollectionType': 'movies'},
          if (!_asRiley(r)) ...[
            {'Id': 'l2', 'Name': 'Shows', 'CollectionType': 'tvshows'},
            {'Id': collectionsViewId, 'Name': 'Collections', 'CollectionType': 'boxsets'},
          ],
        ]));
      case '/UserItems/Resume':
        return FakeReply.json(_items([...movies, ..._allEpisodes].where((m) => resumeIds.contains(m['Id']))));
      case '/Shows/NextUp':
        final series = q['seriesId'];
        final (season, episode) = nextUpEpisode;
        final next = _allEpisodes.where((e) => (series == null || e['SeriesId'] == series) && e['IndexNumber'] == episode && e['ParentIndexNumber'] == season);
        return FakeReply.json(_items(next.take(1)));
      case '/Items/Latest':
        return FakeReply.json(movies.reversed.take(6).map(_fresh).toList());
      case '/Persons':
        return FakeReply.json(_items(const []));
      case '/Items':
        return FakeReply.json(_items(_query(q)));
    }

    final seasons = RegExp(r'^/Shows/([^/]+)/Seasons$').firstMatch(path);
    if (seasons != null) return FakeReply.json(_items(_seasons[seasons[1]] ?? const []));
    final showEpisodes = RegExp(r'^/Shows/([^/]+)/Episodes$').firstMatch(path);
    if (showEpisodes != null) {
      return FakeReply.json(_items(_allEpisodes.where((e) => e['SeriesId'] == showEpisodes[1])));
    }
    final segmentsOf = RegExp(r'^/MediaSegments/([^/]+)$').firstMatch(path);
    if (segmentsOf != null) {
      final found = segments[segmentsOf[1]] ?? const [];
      return FakeReply.json({'Items': found, 'TotalRecordCount': found.length});
    }
    final similar = RegExp(r'^/Items/([^/]+)/Similar$').firstMatch(path);
    // Every other film: enough to scroll the More like this row.
    if (similar != null) return FakeReply.json(_items(movies.where((m) => m['Id'] != similar[1])));
    final item = RegExp(r'^/Items/([^/]+)$').firstMatch(path);
    if (item != null) {
      final found = _byId(item[1]!);
      return found == null ? FakeReply.json({}, status: 404) : FakeReply.json(_detail(found));
    }
    if (path.endsWith('.vtt')) {
      return FakeReply.bytes('WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nHello.\n'.codeUnits, contentType: 'text/vtt');
    }
    return null;
  }

  Iterable<Map<String, Object?>> _query(Map<String, String> q) {
    // A person's filmography: every film (the whole cast is in all of them).
    if (q['personIds'] != null) return movies;
    if (q['ids'] case final ids?) {
      return ids.split(',').where((id) => !unfindable.contains(id)).map(_byId).whereType<Map<String, Object?>>();
    }
    if (q['isFavorite'] == 'true') return [...movies, ...shows].where((i) => favoriteIds.contains(i['Id']));
    if (q['searchTerm'] case final term?) {
      final t = term.toLowerCase();
      return [...movies, ...shows].where((i) => '${i['Name']}'.toLowerCase().contains(t));
    }
    if (q['isPlayed'] == 'true') return movies.where((m) => playedIds.contains(m['Id']));
    if (q['isPlayed'] == 'false') return movies.where((m) => !playedIds.contains(m['Id'])).take(6);
    switch (q['parentId']) {
      case collectionsViewId when q['includeItemTypes'] == 'BoxSet':
        return collections;
      case final c? when collectionMembers.containsKey(c):
        return collectionMembers[c]!.map(_byId).whereType<Map<String, Object?>>();
      case 'l1':
        return movies;
      case 'l2':
        return shows;
      case final parent?:
        return _episodes[parent] ?? const [];
    }
    return const [];
  }
}
