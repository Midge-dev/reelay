import 'fake_http.dart';

/// A small Jellyfin server — two libraries, eight films, two shows — that
/// answers what JellyfinClient asks, shaped like a real 12.x server
/// (see test/data/jellyfin_client_test.dart for the trimmed originals).
///
/// Journeys read it to know what should be on screen: [movies] in
/// library order, [shows], and what each home row holds.
class FakeJellyfin {
  FakeJellyfin({this.baseUrl = 'http://den.local:8096', this.unfindable = const {}});

  final String baseUrl;

  /// Ids still listed (on the watchlist, say) that a lookup by id no longer
  /// finds — a title removed from the server since.
  final Set<String> unfindable;
  static const userId = 'u1';
  static const serverId = 'jf-den';

  static const movieTitles = ['Arrival', 'Blade Runner', 'Contact', 'Dune', 'Ex Machina', 'Gattaca', 'Her', 'Interstellar'];

  late final List<Map<String, Object?>> movies = [
    for (var i = 0; i < movieTitles.length; i++) _movie('m${i + 1}', movieTitles[i], 1980 + i * 5),
  ];

  late final List<Map<String, Object?>> shows = [
    _show('s1', 'Severance', seasons: 2, episodesPerSeason: 4),
    _show('s2', 'Andor', seasons: 1, episodesPerSeason: 3),
  ];

  final _seasons = <String, List<Map<String, Object?>>>{};
  final _episodes = <String, List<Map<String, Object?>>>{};

  /// Part-watched (Continue Watching), favourited (the watchlist), played.
  final resumeIds = {'m2'};
  final favoriteIds = {'m3', 's2'};
  final playedIds = {'m4'};

  /// What playback reported, as `/Sessions/Playing…` paths.
  final playbackReports = <String>[];

  Map<String, Object?> _userData(String id, {int? runTicks}) => {
    'PlaybackPositionTicks': resumeIds.contains(id) && runTicks != null ? runTicks ~/ 3 : 0,
    'PlayCount': playedIds.contains(id) ? 1 : 0,
    'Played': playedIds.contains(id),
    'IsFavorite': favoriteIds.contains(id),
    if (resumeIds.contains(id)) 'LastPlayedDate': '2026-11-17T20:00:00.0000000Z',
  };

  Map<String, Object?> _movie(String id, String name, int year) {
    const ticks = 72000000000; // 2 hours
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

  Iterable<Map<String, Object?>> get _allEpisodes => _episodes.values.expand((e) => e);

  Map<String, Object?>? _byId(String id) {
    for (final item in [...movies, ...shows, ..._seasons.values.expand((s) => s), ..._allEpisodes]) {
      if (item['Id'] == id) return item;
    }
    return null;
  }

  Map<String, Object?> _detail(Map<String, Object?> item) => {
    ...item,
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
            {'Type': 'Audio', 'Codec': 'eac3', 'Index': 1, 'Channels': 6, 'IsDefault': true, 'Language': 'eng', 'DisplayTitle': 'English - Dolby Digital+ - 5.1'},
            {'Type': 'Subtitle', 'Codec': 'subrip', 'Index': 2, 'Language': 'eng', 'DisplayTitle': 'English', 'IsExternal': true, 'DeliveryUrl': '/Videos/${item['Id']}/${item['Id']}/Subtitles/2/0/Stream.vtt'},
          ],
        },
      ],
    'People': [
      {'Name': 'Ada Director', 'Id': 'pd', 'Type': 'Director'},
      {'Name': 'Lee Lead', 'Id': 'pa', 'Role': 'The lead', 'Type': 'Actor'},
    ],
    'Studios': [
      {'Name': 'Fake Studio'},
    ],
  };

  Map<String, Object?> _items(Iterable<Map<String, Object?>> items) {
    final list = items.toList();
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
      playbackReports.add(path);
      return FakeReply.empty();
    }
    if (r.method == 'POST' || r.method == 'DELETE') {
      final fav = RegExp(r'^/UserFavoriteItems/(.+)$').firstMatch(path);
      if (fav != null) r.method == 'POST' ? favoriteIds.add(fav[1]!) : favoriteIds.remove(fav[1]!);
      return FakeReply.json({});
    }

    switch (path) {
      case '/System/Info/Public':
        return FakeReply.json({'ServerName': 'Den', 'Id': 'jf-den', 'Version': '12.1.0'});
      case '/Users/Me':
        return FakeReply.json({'Id': userId, 'Name': 'sam'});
      case '/UserViews':
        return FakeReply.json(_items([
          {'Id': 'l1', 'Name': 'Movies', 'CollectionType': 'movies'},
          {'Id': 'l2', 'Name': 'Shows', 'CollectionType': 'tvshows'},
        ]));
      case '/UserItems/Resume':
        return FakeReply.json(_items(movies.where((m) => resumeIds.contains(m['Id']))));
      case '/Shows/NextUp':
        final series = q['seriesId'];
        final next = _allEpisodes.where((e) => (series == null || e['SeriesId'] == series) && e['IndexNumber'] == 2 && e['ParentIndexNumber'] == 1);
        return FakeReply.json(_items(next.take(1)));
      case '/Items/Latest':
        return FakeReply.json(movies.reversed.take(6).toList());
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
    final similar = RegExp(r'^/Items/([^/]+)/Similar$').firstMatch(path);
    if (similar != null) return FakeReply.json(_items(movies.where((m) => m['Id'] != similar[1]).take(4)));
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
