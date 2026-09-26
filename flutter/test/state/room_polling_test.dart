import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/state/app_root_controller.dart';
import 'package:reelay/state/app_state.dart';
import 'package:reelay/state/duplicate_fold.dart';
import 'package:reelay/sync/relay_client.dart';

const _server = PlexServer(name: 'Loft', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'loft');
const _servers = [ReachableServer(_server, ServerReachability.local)];
const _group = SectionGroup(type: 'movie', title: 'Movies', sectionsByServerId: {});
const _home = Home(
  servers: _servers,
  sectionGroups: [_group],
  onDeck: [],
  recentlyAdded: [],
  recentActivity: [],
  suggestions: [],
);
const _ctx = LibraryContext(servers: _servers, sectionGroups: [_group], selectedSectionGroup: _group, items: []);
const _movie = PlexLibraryItem(ratingKey: '1', title: 'Arrival', type: 'movie');

void main() {
  test('rooms are polled on every screen the rooms panel opens over, not only Home', () {
    const copy = Sourced(_movie, _server, ServerReachability.local);
    final detail = MovieDetail(ctx: _ctx, work: FoldedWork(null, const [copy]), activeCopy: copy, returnState: _home);
    for (final state in <AppState>[
      _home,
      const Library(ctx: _ctx, returnState: _home),
      const Search(ctx: _ctx, returnState: _home),
      const Watchlist(ctx: _ctx, returnState: _home),
      const Settings(ctx: _ctx, returnState: _home),
      detail,
      const LoadingHome(servers: _servers, sectionGroups: [_group]),
    ]) {
      expect(pollsLiveRooms(state), isTrue, reason: '${state.runtimeType}');
    }
  });

  test('rooms are not polled while signing in, or in the player', () {
    for (final state in <AppState>[
      const Checking(),
      const LoggedOut(),
      const ConnectingToServer(),
      const Player(server: _server, detail: PlexMovieDetail(ratingKey: '1', title: 'Arrival'), returnState: _home),
    ]) {
      expect(pollsLiveRooms(state), isFalse, reason: '${state.runtimeType}');
    }
  });

  group("a host's kept-open room", () {
    final room = RelayClient('wss://relay.example.com', const RelayIdentity(peerId: 'me'));
    final other = RelayClient('wss://relay.example.com', const RelayIdentity(peerId: 'me'));
    const detail = PlexMovieDetail(ratingKey: '1', title: 'Arrival');
    Lobby lobby(RelayClient relay) =>
        Lobby(server: _server, detail: detail, returnState: _home, relay: relay, hostName: 'Sean', relayNickname: 'Home');

    test('stays open while the host browses', () {
      expect(parkedRoomOnEntering(_home, room), ParkedRoom.keep);
      expect(parkedRoomOnEntering(const Search(ctx: _ctx, returnState: _home), room), ParkedRoom.keep);
      expect(parkedRoomOnEntering(const Library(ctx: _ctx, returnState: _home), room), ParkedRoom.keep);
    });

    test("is taken up again by its own lobby or player", () {
      expect(parkedRoomOnEntering(lobby(room), room), ParkedRoom.resume);
      expect(
        parkedRoomOnEntering(Player(server: _server, detail: detail, returnState: _home, relay: room), room),
        ParkedRoom.resume,
      );
    });

    test('ends for a solo film, another room, or signing out', () {
      expect(parkedRoomOnEntering(const Player(server: _server, detail: detail, returnState: _home), room), ParkedRoom.end);
      expect(parkedRoomOnEntering(lobby(other), room), ParkedRoom.end);
      expect(parkedRoomOnEntering(const LoggedOut(), room), ParkedRoom.end);
    });
  });
}
