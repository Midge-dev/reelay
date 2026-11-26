import 'fake_http.dart';

/// One `/:/timeline` report the app sent, as Plex Media Server sees it.
class PlexTimeline {
  PlexTimeline(this.state, this.ratingKey, this.timeMs, this.sessionIdentifier);
  final String state; // 'playing', 'paused', 'stopped'
  final String ratingKey;
  final int timeMs;

  /// X-Plex-Session-Identifier — must match the stream's, or PMS's
  /// dashboard shows the session wrongly.
  final String? sessionIdentifier;

  @override
  String toString() => '$state $ratingKey @${timeMs ~/ 1000}s';
}

/// A Plex account with one server — "Attic", two real libraries (Movies,
/// TV Shows) plus a home-video one the app should hide — answering what
/// PlexAuthApi, PlexResourcesApi, PlexWatchlistApi and PlexClient ask,
/// shaped like plex.tv and a real PMS (MediaContainer-wrapped JSON,
/// numeric ratingKeys, ms durations; see plezy's plex_client.dart and
/// ARCHITECTURE.md §3).
///
/// The library holds the same eight films and two shows as [FakeJellyfin],
/// with the same IMDb/TVDB ids, so a profile with both folds them
/// together. Journeys read it to know what should be on screen.
class FakePlex {
  FakePlex({this.lanReachable = true, this.remoteReachable = true});

  /// Whether the server's LAN address answers. Off: only the plex.direct
  /// remote address (and then the relay) can reach it.
  bool lanReachable;

  /// Whether the remote (plex.direct) address answers.
  bool remoteReachable;

  /// Whether Plex Relay (Plex's own last-resort proxy) answers.
  bool relayReachable = true;

  /// How long the LAN address takes to answer — a busy Wi-Fi, say.
  Duration lanLatency = Duration.zero;

  /// How long the server takes on every address (artwork aside) — a busy
  /// server on a cold start. Under the app's 4 s probe, or it's dead.
  Duration latency = Duration.zero;

  /// Plex refusing the account token — the TV removed from the account.
  /// Linking again ([linkPin]) gets a new token, [relinkedToken]; the old
  /// one stays refused.
  bool revoked = false;

  /// Whether plex.tv answers at all.
  bool plexTvReachable = true;

  static const accountToken = 'plex-account-token';
  static const relinkedToken = 'plex-account-token-relinked';
  static const serverToken = 'attic-server-token';
  static const machineId = 'attic-machine-id';
  static const username = 'sam';

  static const lanUrl = 'http://192.168.1.20:32400';
  static const remoteUrl = 'https://203-0-113-9.attic.plex.direct:32400';
  static const relayUrl = 'https://203-0-113-9.attic.plex.direct:8443';

  /// The address the app reached the server on, as the last request came.
  String? lastBaseUrl;

  static const movieTitles = ['Arrival', 'Blade Runner', 'Contact', 'Dune', 'Ex Machina', 'Gattaca', 'Her', 'Interstellar'];

  /// ratingKey of film [i] (0-based): 101 … 108.
  static String movieKey(int i) => '${101 + i}';

  static const filmMs = 100 * 60000; // as long as the fake player's files
  static const episodeMs = 50 * 60000;

  late final List<Map<String, Object?>> movies = [
    for (var i = 0; i < movieTitles.length; i++) _movie(movieKey(i), 'm${i + 1}', movieTitles[i], 1980 + i * 5),
  ];

  final _seasons = <String, List<Map<String, Object?>>>{};
  final _episodes = <String, List<Map<String, Object?>>>{};

  late final List<Map<String, Object?>> shows = [
    _show('201', 's1', 'Severance', seasons: 2, episodesPerSeason: 4),
    _show('202', 's2', 'Andor', seasons: 1, episodesPerSeason: 3),
  ];

  late final collections = <Map<String, Object?>>[
    {'ratingKey': '301', 'key': '/library/collections/301/children', 'type': 'collection', 'title': 'Sci-fi favourites', 'childCount': 3, 'thumb': '/library/collections/301/thumb/1'},
    {'ratingKey': '302', 'key': '/library/collections/302/children', 'type': 'collection', 'title': 'Eighties', 'childCount': 2, 'thumb': '/library/collections/302/thumb/1'},
  ];
  static const collectionMembers = {
    '301': ['101', '105', '108'],
    '302': ['101', '102'],
  };

  /// Saved positions (ms). Blade Runner is a third of the way in, as on
  /// the Jellyfin fake.
  final viewOffsets = <String, int>{'102': filmMs ~/ 3};

  /// Times fully watched.
  final viewCounts = <String, int>{'104': 1};

  /// When each title was last watched (seconds since epoch).
  final lastViewedAt = <String, int>{'102': 1763409600};

  /// Episodes Plex's On Deck offers next (no position of their own).
  final onDeckEpisodes = <String>{'2011-2'};

  /// Discover-universe watchlist, as plex.tv keeps it: guids.
  final watchlistGuids = <String>['plex://movie/m3', 'plex://show/s2'];

  /// Intro / credits markers by episode: Severance's have both, Andor's
  /// none, like the Jellyfin fake.
  static const introStartMs = 60000, introEndMs = 150000, creditsStartMs = 95 * 60000;

  /// What `/:/timeline` heard, in order.
  final timelines = <PlexTimeline>[];

  /// Server-side stream selections (`PUT /library/parts/{id}`), as
  /// "audio=…, subtitle=…".
  final streamSelections = <String>[];

  /// Transcoder requests: 'decision', 'start', 'stop', with the session.
  final transcodes = <String>[];

  /// What `/decision` answers. Null streams; a string refuses, in Plex's
  /// own words (generalDecisionCode 2000+).
  String? transcodeRefusal;

  /// Sign-in PIN state: linked once [linkPin] runs (the person typed the
  /// code at plex.tv/link).
  bool _pinLinked = false;
  void linkPin() => _pinLinked = true;
  static const pinCode = 'R3LY';

  Map<String, Object?> _guids(String fakeId, {bool show = false}) => {
    'guid': 'plex://${show ? 'show' : 'movie'}/$fakeId',
    'Guid': [
      show ? {'id': 'tvdb://9$fakeId'} : {'id': 'imdb://tt00$fakeId'},
    ],
  };

  Map<String, Object?> _movie(String key, String fakeId, String title, int year) => {
    'ratingKey': key,
    'key': '/library/metadata/$key',
    'type': 'movie',
    'title': title,
    'year': year,
    'originallyAvailableAt': '$year-06-01',
    'addedAt': 1767225600 + int.parse(key),
    'contentRating': 'PG-13',
    'summary': '$title, a film.',
    'duration': filmMs,
    'thumb': '/library/metadata/$key/thumb/1',
    'art': '/library/metadata/$key/art/1',
    'librarySectionID': 1,
    'Genre': [
      {'tag': 'Science Fiction'},
    ],
    ..._guids(fakeId),
  };

  Map<String, Object?> _show(String key, String fakeId, String title, {required int seasons, required int episodesPerSeason}) {
    final seasonList = <Map<String, Object?>>[];
    for (var s = 1; s <= seasons; s++) {
      final seasonKey = '$key$s';
      seasonList.add({
        'ratingKey': seasonKey,
        'key': '/library/metadata/$seasonKey/children',
        'type': 'season',
        'title': 'Season $s',
        'index': s,
        'parentRatingKey': key,
        'parentTitle': title,
        'thumb': '/library/metadata/$seasonKey/thumb/1',
      });
      _episodes[seasonKey] = [
        for (var e = 1; e <= episodesPerSeason; e++)
          {
            'ratingKey': '$seasonKey-$e',
            'key': '/library/metadata/$seasonKey-$e',
            'type': 'episode',
            'title': '$title ${s}x$e',
            'index': e,
            'parentIndex': s,
            'parentRatingKey': seasonKey,
            'grandparentRatingKey': key,
            'grandparentTitle': title,
            'summary': 'Episode $e of season $s.',
            'duration': episodeMs,
            'originallyAvailableAt': '2022-0$s-${(10 + e)}',
            'thumb': '/library/metadata/$seasonKey-$e/thumb/1',
            'grandparentThumb': '/library/metadata/$key/thumb/1',
            'guid': 'plex://episode/$fakeId-$s-$e',
            'Guid': [
              {'id': 'tvdb://9${fakeId}0${s}0$e'},
            ],
          },
      ];
    }
    _seasons[key] = seasonList;
    return {
      'ratingKey': key,
      'key': '/library/metadata/$key/children',
      'type': 'show',
      'title': title,
      'year': 2022,
      'summary': '$title, a show.',
      'contentRating': 'TV-MA',
      'childCount': seasons,
      'leafCount': seasons * episodesPerSeason,
      'thumb': '/library/metadata/$key/thumb/1',
      'art': '/library/metadata/$key/art/1',
      'librarySectionID': 2,
      'Genre': [
        {'tag': 'Drama'},
      ],
      ..._guids(fakeId, show: true),
    };
  }

  Iterable<Map<String, Object?>> get _allEpisodes {
    shows;
    return _episodes.values.expand((e) => e);
  }

  Map<String, Object?>? _byKey(String key) {
    for (final item in [...movies, ...shows, ...collections, ..._seasons.values.expand((s) => s), ..._allEpisodes]) {
      if (item['ratingKey'] == key) return item;
    }
    return null;
  }

  /// An item as served now: its watch state read afresh, so what the
  /// timeline reported shows on the next fetch, as on a real server.
  Map<String, Object?> _fresh(Map<String, Object?> item) {
    final key = item['ratingKey']! as String;
    return {
      ...item,
      'viewOffset': ?viewOffsets[key],
      'viewCount': ?viewCounts[key],
      'lastViewedAt': ?lastViewedAt[key],
    };
  }

  Map<String, Object?> _detail(Map<String, Object?> item) {
    final key = item['ratingKey']! as String;
    final playable = item['type'] == 'movie' || item['type'] == 'episode';
    final partId = int.parse(key.replaceAll('-', ''));
    return {
      ..._fresh(item),
      if (playable)
        'Media': [
          {
            'videoCodec': 'h264',
            'audioCodec': 'eac3',
            'container': 'mkv',
            'videoResolution': '1080',
            'audioChannels': 6,
            'bitrate': 8000,
            'Part': [
              {
                'id': partId,
                'key': '/library/parts/$partId/1700000000/file.mkv',
                'container': 'mkv',
                'duration': item['duration'],
                'size': 4000000000,
                'Stream': [
                  {'id': partId * 10 + 1, 'streamType': 1, 'codec': 'h264', 'index': 0, 'frameRate': 23.976, 'width': 1920, 'height': 1080, 'displayTitle': '1080p (H.264)'},
                  {'id': partId * 10 + 2, 'streamType': 2, 'codec': 'eac3', 'index': 1, 'channels': 6, 'language': 'English', 'languageCode': 'eng', 'selected': true, 'displayTitle': 'English (EAC3 5.1)'},
                  {'id': partId * 10 + 3, 'streamType': 3, 'codec': 'srt', 'key': '/library/streams/${partId * 10 + 3}', 'language': 'English', 'languageCode': 'eng', 'displayTitle': 'English (SRT External)'},
                ],
              },
            ],
          },
        ],
      'studio': 'Fake Studio',
      'Director': [
        {'id': 900, 'tag': 'Ada Director', 'tagKey': 'person-ada'},
      ],
      // A full cast, as a real title has: enough to scroll the Cast & crew row.
      'Role': [
        {'id': 901, 'tag': 'Lee Lead', 'role': 'The lead', 'tagKey': 'person-lee'},
        for (var i = 1; i <= 10; i++) {'id': 910 + i, 'tag': 'Cast Member $i', 'role': 'Role $i', 'tagKey': 'person-c$i'},
      ],
    };
  }

  Map<String, Object?> _container(String key, Iterable<Map<String, Object?>> items, {Map<String, Object?> extra = const {}}) {
    final list = items.toList();
    return {
      'MediaContainer': {'size': list.length, key: list, ...extra},
    };
  }

  Map<String, Object?> _metadata(Iterable<Map<String, Object?>> items) => _container('Metadata', items.map(_fresh));

  Map<String, Object?> _hub(String id, String title, String type, Iterable<Map<String, Object?>> items) {
    final list = items.map(_fresh).toList();
    return {'hubIdentifier': id, 'title': title, 'type': type, 'size': list.length, 'Metadata': list};
  }

  /// Part-watched films and the next episodes Plex would put On Deck.
  List<Map<String, Object?>> get _onDeck => [
    ...movies.where((m) => viewOffsets.containsKey(m['ratingKey'])),
    ..._allEpisodes.where((e) => viewOffsets.containsKey(e['ratingKey']) || onDeckEpisodes.contains(e['ratingKey'])),
  ];

  bool _hasToken(FakeRequest r, String token) =>
      r.headers['x-plex-token'] == token || r.uri.queryParameters['X-Plex-Token'] == token;

  /// The token a linked PIN hands out: a fresh one after a revocation.
  String get _issuedToken => revoked ? relinkedToken : accountToken;

  bool _hasAccountToken(FakeRequest r) =>
      revoked ? _pinLinked && _hasToken(r, relinkedToken) : _hasToken(r, accountToken);

  static final _origins = {Uri.parse(lanUrl).origin, Uri.parse(remoteUrl).origin, Uri.parse(relayUrl).origin};

  /// The route to hand FakeNetwork.
  FakeReply? route(FakeRequest r) {
    final host = r.uri.host;
    // Artwork plex.tv serves itself: the account's avatar, Discover posters.
    if (host == 'metadata-static.plex.tv' || (host == 'plex.tv' && r.uri.path.endsWith('/avatar'))) {
      return FakeReply.bytes(transparentPng, contentType: 'image/png');
    }
    if (host == 'plex.tv') return plexTvReachable ? _plexTv(r) : null;
    if (host == 'discover.provider.plex.tv') return _discover(r);
    if (!_origins.contains(r.uri.origin)) return null;
    final reachable = switch (r.uri.origin) {
      final o when o == Uri.parse(lanUrl).origin => lanReachable,
      final o when o == Uri.parse(remoteUrl).origin => remoteReachable,
      _ => relayReachable,
    };
    if (!reachable) return null; // refused, like a host that isn't there
    lastBaseUrl = r.uri.origin;
    final reply = _server(r);
    if (r.uri.origin == Uri.parse(lanUrl).origin) reply?.delay = lanLatency;
    if (latency > Duration.zero && !r.uri.path.contains('/thumb') && !r.uri.path.contains('/art') && !r.uri.path.startsWith('/photo')) {
      reply?.delay += latency;
    }
    return reply;
  }

  FakeReply? _plexTv(FakeRequest r) {
    final path = r.uri.path;
    if (r.method == 'POST' && path == '/api/v2/pins') {
      return FakeReply.json({'id': 4242, 'code': pinCode, 'expiresIn': 900}, status: 201);
    }
    if (path == '/api/v2/pins/4242') {
      return FakeReply.json({'id': 4242, 'code': pinCode, 'expiresIn': 900, 'authToken': _pinLinked ? _issuedToken : null});
    }
    if (!_hasAccountToken(r)) return FakeReply.json({'errors': [{'code': 1001, 'message': 'User could not be authenticated'}]}, status: 401);
    switch (path) {
      case '/api/v2/user':
        return FakeReply.json({'id': 7, 'uuid': 'acct-sam', 'username': username, 'title': username, 'thumb': 'https://plex.tv/users/acct-sam/avatar'});
      case '/api/v2/resources':
        // A bare array, unlike PMS's own MediaContainer-wrapped answers.
        return FakeReply.json([
          {
            'name': 'Attic',
            'product': 'Plex Media Server',
            'provides': 'server',
            'owned': true,
            'clientIdentifier': machineId,
            'accessToken': serverToken,
            'connections': [
              {'protocol': 'http', 'address': '192.168.1.20', 'port': 32400, 'uri': lanUrl, 'local': true, 'relay': false},
              {'protocol': 'https', 'address': '203.0.113.9', 'port': 32400, 'uri': remoteUrl, 'local': false, 'relay': false},
              {'protocol': 'https', 'address': '203.0.113.9', 'port': 8443, 'uri': relayUrl, 'local': false, 'relay': true},
            ],
          },
          // A phone on the account: not a server, never probed.
          {'name': "Sam's phone", 'product': 'Plex for iOS', 'provides': 'client,player', 'owned': true, 'clientIdentifier': 'phone-1', 'connections': <Object>[]},
        ]);
    }
    return null;
  }

  FakeReply? _discover(FakeRequest r) {
    if (!_hasAccountToken(r)) return FakeReply.json({}, status: 401);
    final path = r.uri.path;
    if (path == '/library/sections/watchlist/all') {
      return FakeReply.json(_container('Metadata', [
        for (final guid in watchlistGuids)
          if (_byGuid(guid) case final local?)
            {
              'ratingKey': guid.substring(guid.lastIndexOf('/') + 1),
              'guid': guid,
              'type': local['type'],
              'title': local['title'],
              'year': local['year'],
              'thumb': 'https://metadata-static.plex.tv/${local['ratingKey']}.jpg',
              'addedAt': 1763400000,
            },
      ]));
    }
    final key = r.uri.queryParameters['ratingKey'];
    if (r.method == 'PUT' && key != null) {
      final guid = [...movies, ...shows].map((i) => i['guid']! as String).firstWhere((g) => g.endsWith('/$key'), orElse: () => '');
      if (path == '/actions/addToWatchlist' && guid.isNotEmpty && !watchlistGuids.contains(guid)) watchlistGuids.insert(0, guid);
      if (path == '/actions/removeFromWatchlist') watchlistGuids.remove(guid);
      return FakeReply.json({});
    }
    return null;
  }

  Map<String, Object?>? _byGuid(String guid) {
    for (final i in [...movies, ...shows]) {
      if (i['guid'] == guid) return i;
    }
    return null;
  }

  FakeReply? _server(FakeRequest r) {
    final path = r.uri.path;
    final q = r.uri.queryParameters;
    if (path == '/photo/:/transcode' || RegExp(r'/(thumb|art)/\d+$').hasMatch(path)) {
      return FakeReply.bytes(transparentPng, contentType: 'image/png');
    }
    if (!_hasToken(r, serverToken)) return FakeReply.json({}, status: 401);

    if (path.startsWith('/video/:/transcode/universal/')) {
      final kind = path.split('/').last.replaceAll('.m3u8', '');
      transcodes.add('$kind ${q['session']}');
      if (kind == 'decision') {
        return FakeReply.json({
          'MediaContainer': transcodeRefusal == null
              ? {'generalDecisionCode': 1000, 'generalDecisionText': 'Direct play OK.', 'transcodeDecisionCode': 1001, 'transcodeDecisionText': 'Transcoding.'}
              : {'generalDecisionCode': 2000, 'generalDecisionText': transcodeRefusal},
        });
      }
      if (kind == 'start') {
        return FakeReply.bytes('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\nsession/x/base/index.m3u8\n'.codeUnits, contentType: 'application/vnd.apple.mpegurl');
      }
      return FakeReply.empty(status: 200);
    }
    if (path == '/:/timeline') {
      final key = q['ratingKey']!;
      final state = q['state']!;
      final time = int.parse(q['time'] ?? '0');
      timelines.add(PlexTimeline(state, key, time, r.headers['x-plex-session-identifier']));
      final duration = (_byKey(key)?['duration'] as int?) ?? 0;
      // As PMS keeps it: past 90% the title is watched and leaves On Deck;
      // otherwise the spot is saved.
      if (duration > 0 && time >= duration * 0.9) {
        viewOffsets.remove(key);
        onDeckEpisodes.remove(key);
        viewCounts[key] = (viewCounts[key] ?? 0) + 1;
      } else if (time > 0) {
        viewOffsets[key] = time;
      }
      lastViewedAt[key] = 1763500000 + timelines.length;
      return FakeReply.empty(status: 200);
    }
    final part = RegExp(r'^/library/parts/(\d+)$').firstMatch(path);
    if (r.method == 'PUT' && part != null) {
      streamSelections.add('audio=${q['audioStreamID']}, subtitle=${q['subtitleStreamID']}');
      return FakeReply.empty(status: 200);
    }
    if (r.method == 'PUT' && path == '/actions/removeFromContinueWatching') {
      viewOffsets.remove(q['ratingKey']);
      onDeckEpisodes.remove(q['ratingKey']);
      return FakeReply.empty(status: 200);
    }
    if (path.startsWith('/library/streams/')) {
      return FakeReply.bytes('1\n00:00:01,000 --> 00:00:04,000\nHello.\n'.codeUnits, contentType: 'text/srt');
    }

    switch (path) {
      case '/identity':
        return FakeReply.json({'MediaContainer': {'size': 0, 'claimed': true, 'machineIdentifier': machineId, 'version': '1.41.3.9314'}});
      case '/library/sections':
        return FakeReply.json(_container('Directory', [
          {'key': '1', 'title': 'Movies', 'type': 'movie', 'agent': 'tv.plex.agents.movie'},
          {'key': '2', 'title': 'TV Shows', 'type': 'show', 'agent': 'tv.plex.agents.series'},
          // Plex's "Other Videos": no agent, no posters — the app hides it.
          {'key': '3', 'title': 'Home Videos', 'type': 'movie', 'agent': 'com.plexapp.agents.none'},
        ]));
      case '/library/onDeck':
        return FakeReply.json(_metadata(_onDeck));
      case '/library/recentlyAdded':
        return FakeReply.json(_metadata(movies.reversed.take(6)));
      case '/hubs/promoted':
        // No account-level Suggested hub (needs Discover): the app falls
        // back to each library's own.
        return FakeReply.json(_container('Hub', const []));
      case '/library/all':
        final guid = q['guid'];
        return FakeReply.json(_metadata([...movies, ...shows].where((i) => i['guid'] == guid)));
      case '/hubs/search':
        final term = (q['query'] ?? '').toLowerCase();
        bool hit(Map<String, Object?> i) => '${i['title']}'.toLowerCase().contains(term);
        final people = [
          {'id': 901, 'tag': 'Lee Lead', 'tagKey': 'person-lee', 'type': 'tag', 'tagType': 6},
          {'id': 900, 'tag': 'Ada Director', 'tagKey': 'person-ada', 'type': 'tag', 'tagType': 4},
        ].where((p) => '${p['tag']}'.toLowerCase().contains(term));
        return FakeReply.json(_container('Hub', [
          _hub('movie', 'Movies', 'movie', movies.where(hit)),
          _hub('show', 'Shows', 'show', shows.where(hit)),
          {'hubIdentifier': 'actor', 'title': 'Actors', 'type': 'actor', 'size': people.length, 'Directory': people.toList()},
        ]));
    }

    final sectionAll = RegExp(r'^/library/sections/(\d+)/all$').firstMatch(path);
    if (sectionAll != null) {
      return FakeReply.json(_metadata(switch (sectionAll[1]) {
        '1' => movies,
        '2' => shows,
        _ => const [],
      }));
    }
    final sectionCollections = RegExp(r'^/library/sections/(\d+)/collections$').firstMatch(path);
    if (sectionCollections != null) return FakeReply.json(_metadata(sectionCollections[1] == '1' ? collections : const []));
    final sectionHubs = RegExp(r'^/hubs/sections/(\d+)$').firstMatch(path);
    if (sectionHubs != null) {
      final films = sectionHubs[1] == '1';
      final pool = films ? movies : shows;
      return FakeReply.json(_container('Hub', [
        _hub(films ? 'movie.recentlyviewed.1' : 'tv.recentlyviewed.2', 'Recently Watched', films ? 'movie' : 'show', pool.where((i) => viewCounts.containsKey(i['ratingKey']))),
        _hub(films ? 'movie.topunwatched.1' : 'tv.topunwatched.2', 'Top Unwatched', films ? 'movie' : 'show', pool.where((i) => !viewCounts.containsKey(i['ratingKey'])).take(6)),
      ]));
    }
    final people = RegExp(r'^/library/people/(\d+)/media$').firstMatch(path);
    if (people != null) return FakeReply.json(_metadata(movies));

    final related = RegExp(r'^/library/metadata/([^/]+)/related$').firstMatch(path);
    if (related != null) {
      return FakeReply.json(_container('Hub', [
        _hub('movie.similar', 'More Like This', 'movie', movies.where((m) => m['ratingKey'] != related[1])),
      ]));
    }
    final children = RegExp(r'^/library/metadata/([^/]+)/children$').firstMatch(path);
    if (children != null) {
      final key = children[1]!;
      if (collectionMembers[key] case final members?) return FakeReply.json(_metadata(members.map(_byKey).whereType<Map<String, Object?>>()));
      return FakeReply.json(_metadata(_seasons[key] ?? _episodes[key] ?? const []));
    }
    final item = RegExp(r'^/library/metadata/([^/]+)$').firstMatch(path);
    if (item != null) {
      final found = _byKey(item[1]!);
      if (found == null) return FakeReply.json({'MediaContainer': {'size': 0}}, status: 404);
      final detail = _detail(found);
      if (q['includeMarkers'] == '1' && found['grandparentRatingKey'] == '201') {
        detail['Marker'] = [
          {'type': 'intro', 'startTimeOffset': introStartMs, 'endTimeOffset': introEndMs},
          {'type': 'credits', 'startTimeOffset': creditsStartMs, 'endTimeOffset': episodeMs, 'final': true},
        ];
      }
      if (q['includeOnDeck'] == '1' && found['type'] == 'show') {
        final next = _onDeck.where((e) => e['grandparentRatingKey'] == found['ratingKey']).take(1).map(_fresh).toList();
        if (next.isNotEmpty) detail['OnDeck'] = {'Metadata': next};
      }
      return FakeReply.json({
        'MediaContainer': {
          'size': 1,
          'Metadata': [detail],
        },
      });
    }
    return null;
  }
}
