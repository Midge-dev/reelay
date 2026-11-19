import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/media/media_server_client.dart';
import 'package:reelay/playback/next_episode.dart';
import 'package:reelay/state/room_title.dart';
import 'package:reelay/sync/episode_switch.dart';

/// A server with shows laid out as {showId: {season: episodeCount}}, ids
/// like "$showId-s$season-e$episode", plus anything in [details].
class _Shows implements MediaServerClient {
  _Shows(this.server, this.shows, {this.searchHits = const []});

  @override
  final MediaServer server;
  final Map<String, Map<int, int>> shows;
  final List<MediaItem> searchHits;

  @override
  Future<List<MediaItem>> fetchSeasons(String showId) async => [
    for (final season in (shows[showId] ?? const {}).keys)
      MediaItem(id: '$showId-s$season', kind: MediaKind.season, title: 'Season $season', index: season),
  ];

  @override
  Future<List<MediaItem>> fetchEpisodes(String seasonId) async {
    final showId = seasonId.substring(0, seasonId.lastIndexOf('-s'));
    final season = int.parse(seasonId.substring(seasonId.lastIndexOf('-s') + 2));
    final count = shows[showId]?[season] ?? 0;
    return [
      // Out of order on purpose: servers don't promise an order.
      for (var e = count; e >= 1; e--)
        MediaItem(id: '$seasonId-e$e', kind: MediaKind.episode, title: 'Episode $e', index: e, parentIndex: season),
    ];
  }

  @override
  Future<MediaDetail> fetchDetail(String id) async {
    final m = RegExp(r'^(.+)-s(\d+)-e(\d+)$').firstMatch(id);
    if (m == null) throw StateError('no $id');
    return MediaDetail(id: id, kind: MediaKind.episode, title: 'Episode ${m[3]}', parentIndex: int.parse(m[2]!), index: int.parse(m[3]!), showId: m[1]);
  }

  @override
  Future<List<MediaItem>> search(String query) async => searchHits;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _attic = MediaServer(name: 'Attic', baseUrl: 'http://attic', accessToken: 't', id: 'attic');
const _loft = MediaServer(name: 'Loft', baseUrl: 'http://loft', accessToken: 't', id: 'loft');

void main() {
  group('the episode after this one', () {
    final client = _Shows(_attic, {
      'sev': {0: 2, 1: 3, 2: 2},
    });

    Future<String?> after(int season, int episode) async =>
        (await episodeAfter(client, 'sev', season: season, episode: episode))?.id;

    test('the next in its season', () async => expect(await after(1, 1), 'sev-s1-e2'));
    test('the first of the next season after the last of one', () async => expect(await after(1, 3), 'sev-s2-e1'));
    test('none after the very last', () async => expect(await after(2, 2), isNull));
    test('specials never follow a regular episode', () async => expect(await after(1, 3), isNot(startsWith('sev-s0'))));
    test('a special is followed by the next special, then season 1', () async {
      expect(await after(0, 1), 'sev-s0-e2');
      expect(await after(0, 2), 'sev-s1-e1');
    });

    test('from what is playing: needs to know the show and the numbers', () async {
      const playing = MediaDetail(id: 'x', kind: MediaKind.episode, title: 'E1', parentIndex: 1, index: 1, showId: 'sev');
      expect((await episodeAfterDetail(client, playing))?.id, 'sev-s1-e2');
      const film = MediaDetail(id: 'f', kind: MediaKind.movie, title: 'Film');
      expect(await episodeAfterDetail(client, film), isNull);
    });
  });

  group("a guest finding the room's next episode", () {
    const to = EpisodeSwitch(
      title: 'Severance · S1E3',
      ratingKey: 'host-sev-s1-e3',
      serverId: 'attic',
      ids: ['plex://episode/sev-1-3'],
      mediaTitle: 'Episode 3',
      showTitle: 'Severance',
      showIds: ['tvdb://371980'],
      seasonIndex: 1,
      episodeIndex: 3,
    );

    Future<(MediaServer, MediaDetail)?> resolve(List<_Shows> servers, {MediaServer? current, String? currentShow}) => resolveEpisodeSwitch(
      [for (final s in servers) ReachableServer(s.server, ServerReachability.local)],
      to,
      (server) => servers.firstWhere((s) => s.server.id == server.id),
      currentServer: current,
      currentShowId: currentShow,
    );

    test("sharing the host's server: the host's own item", () async {
      final found = await resolve([
        _Shows(_attic, {'host-sev': {1: 5}}),
      ]);
      expect(found?.$2.id, 'host-sev-s1-e3');
    });

    test('its own copy of the show it is already watching, by season and episode', () async {
      final found = await resolve([
        _Shows(_loft, {'my-sev': {1: 5}}),
      ], current: _loft, currentShow: 'my-sev');
      expect((found?.$1.id, found?.$2.id), ('loft', 'my-sev-s1-e3'));
    });

    test('the show found by title and its ids, when it doesn\'t know the show yet', () async {
      final found = await resolve([
        _Shows(
          _loft,
          {'my-sev': {1: 5}},
          searchHits: const [
            MediaItem(id: 'other', kind: MediaKind.show, title: 'Severance', externalIds: ['tvdb://1']),
            MediaItem(id: 'my-sev', kind: MediaKind.show, title: 'Severance', externalIds: ['tvdb://371980']),
          ],
        ),
      ]);
      expect(found?.$2.id, 'my-sev-s1-e3', reason: 'matched on the show id, not just the title');
    });

    test('nowhere: null, so the guest can say so', () async {
      expect(await resolve([_Shows(_loft, {'my-sev': {1: 2}})], current: _loft, currentShow: 'my-sev'), isNull);
    });
  });
}
