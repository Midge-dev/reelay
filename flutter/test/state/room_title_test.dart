import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/media/media_server_client.dart';
import 'package:reelay/state/room_title.dart';
import 'package:reelay/sync/relay_protocol.dart';

/// A server holding [details] by id, whose search returns [searchHits].
class _FakeClient implements MediaServerClient {
  @override
  final MediaServer server;
  final Map<String, MediaDetail> details;
  final List<MediaItem> searchHits;
  final searches = <String>[];

  _FakeClient(this.server, {this.details = const {}, this.searchHits = const []});

  @override
  Future<MediaDetail> fetchDetail(String id) async =>
      details[id] ?? (throw StateError('This title is no longer available on the server.'));

  @override
  Future<List<MediaItem>> search(String query) async {
    searches.add(query);
    return searchHits;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _plexA = MediaServer(name: 'Attic', baseUrl: 'http://attic', accessToken: 't', id: 'plex-a');
const _plexB = MediaServer(name: 'Loft', baseUrl: 'http://loft', accessToken: 't', id: 'plex-b');
const _jelly = MediaServer(
  backend: MediaBackend.jellyfin,
  name: 'GRIM-TEST',
  baseUrl: 'http://grim:8096',
  accessToken: 't',
  id: 'jf',
  userId: 'u',
);

const _sintelIds = ['imdb://tt1727587', 'tmdb://45745'];

RelayRoomSummary _room({String? ratingKey = '100', String? serverId, List<String> ids = const [], String? mediaTitle}) =>
    RelayRoomSummary(
      roomId: 'r1',
      title: 'Sintel',
      ratingKey: ratingKey,
      serverId: serverId,
      ids: ids,
      mediaTitle: mediaTitle,
      hostName: 'Sam',
      occupants: 1,
      maxSeats: 4,
    );

Future<(MediaServer, MediaDetail)?> _resolve(List<_FakeClient> clients, RelayRoomSummary room) => resolveRoomTitle(
  [for (final c in clients) ReachableServer(c.server, ServerReachability.local)],
  room,
  (server) => clients.firstWhere((c) => c.server.id == server.id),
);

void main() {
  test('a room names every id the title is known by', () {
    const detail = MediaDetail(id: '100', title: 'Sintel', guid: 'plex://movie/5d77', externalIds: _sintelIds);
    expect(roomIdsFor(detail), ['plex://movie/5d77', ..._sintelIds]);
  });

  test('a guest sharing the host\'s server plays the host\'s own item', () async {
    final a = _FakeClient(_plexA, details: {'100': const MediaDetail(id: '100', title: 'Sintel')});
    final found = await _resolve([a], _room(serverId: 'plex-a', ids: _sintelIds, mediaTitle: 'Sintel'));
    expect(found?.$1.id, 'plex-a');
    expect(found?.$2.id, '100');
    expect(a.searches, isEmpty, reason: 'no need to search');
  });

  test('a guest on Jellyfin finds its own copy of a Plex host\'s title by provider id', () async {
    final jelly = _FakeClient(
      _jelly,
      details: {'jf-sintel': const MediaDetail(id: 'jf-sintel', title: 'Sintel')},
      searchHits: const [
        MediaItem(id: 'jf-other', title: 'Sintel: the musical', externalIds: ['imdb://tt0000001']),
        MediaItem(id: 'jf-sintel', title: 'Sintel', externalIds: ['tmdb://45745']),
      ],
    );
    final found = await _resolve([jelly], _room(serverId: 'plex-a', ids: _sintelIds, mediaTitle: 'Sintel'));
    expect(found?.$1.id, 'jf');
    expect(found?.$2.id, 'jf-sintel', reason: 'matched on tmdb, not on the title');
    expect(jelly.searches, ['Sintel']);
  });

  test('another server\'s item id is never tried as if it were ours', () async {
    // plex-b happens to have an item 100 — a different film.
    final b = _FakeClient(_plexB, details: {'100': const MediaDetail(id: '100', title: 'Not Sintel')});
    final found = await _resolve([b], _room(serverId: 'plex-a', ids: _sintelIds, mediaTitle: 'Sintel'));
    expect(found, isNull);
  });

  test('a room from an older host, with only an item id, is tried on every server as before', () async {
    final a = _FakeClient(_plexA);
    final b = _FakeClient(_plexB, details: {'100': const MediaDetail(id: '100', title: 'Sintel')});
    final found = await _resolve([a, b], _room());
    expect(found?.$1.id, 'plex-b');
  });

  test('the host\'s server has lost it: another copy is found by id', () async {
    final a = _FakeClient(_plexA);
    final jelly = _FakeClient(
      _jelly,
      details: {'jf-sintel': const MediaDetail(id: 'jf-sintel', title: 'Sintel')},
      searchHits: const [MediaItem(id: 'jf-sintel', title: 'Sintel', externalIds: _sintelIds)],
    );
    final found = await _resolve([a, jelly], _room(serverId: 'plex-a', ids: _sintelIds, mediaTitle: 'Sintel'));
    expect(found?.$1.id, 'jf');
  });

  test('the room payload round-trips, and an old relay\'s room has none of it', () {
    final full = RelayRoomSummary.fromJson({
      'roomId': 'r1',
      'title': 'Sintel',
      'ratingKey': '100',
      'serverId': 'plex-a',
      'ids': _sintelIds,
      'mediaTitle': 'Sintel',
      'year': 2010,
      'hostName': 'Sam',
      'occupants': 1,
      'maxSeats': 4,
    });
    expect((full.serverId, full.mediaTitle, full.year), ('plex-a', 'Sintel', 2010));
    expect(full.ids, _sintelIds);
    final old = RelayRoomSummary.fromJson({
      'roomId': 'r1',
      'title': 'Sintel',
      'ratingKey': '100',
      'hostName': 'Sam',
      'occupants': 1,
      'maxSeats': 4,
    });
    expect((old.serverId, old.mediaTitle), (null, null));
    expect(old.ids, isEmpty);
  });
}
