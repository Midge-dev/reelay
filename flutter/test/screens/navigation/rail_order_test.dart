import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/navigation/app_navigation_drawer.dart';
import 'package:reelay/screens/navigation/rail_order.dart';
import 'package:reelay/screens/settings/rail_order_list.dart';
import 'package:reelay/state/app_state.dart';
import 'package:reelay/theme/phosphor_icons.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');
const _movies = SectionGroup(type: 'movie', title: 'Movies', sectionsByServerId: {});
const _shows = SectionGroup(type: 'show', title: 'Shows', sectionsByServerId: {});
const _anime = SectionGroup(type: 'show', title: 'Anime', sectionsByServerId: {});
final _moviesId = railSectionId(_movies);
final _showsId = railSectionId(_shows);
final _animeId = railSectionId(_anime);

void main() {
  group('resolveRailOrder', () {
    test('nothing saved is the default order', () {
      expect(resolveRailOrder(const [], [_movies, _shows]), [railHome, railSearch, railWatchlist, _moviesId, _showsId, railRooms]);
    });

    test('a saved order is kept', () {
      final saved = [railRooms, _showsId, railHome, railSearch, railWatchlist, _moviesId];
      expect(resolveRailOrder(saved, [_movies, _shows]), saved);
    });

    test('a library that is gone drops out, and a new one slots in after its default neighbour', () {
      final saved = [railRooms, railHome, railSearch, railWatchlist, _moviesId, 'section:show::gone'];
      expect(
        resolveRailOrder(saved, [_movies, _shows, _anime]),
        [railRooms, railHome, railSearch, railWatchlist, _moviesId, _showsId, _animeId],
      );
    });
  });

  test('moveRailItem moves one place and stops at the ends', () {
    final order = [railHome, railSearch, railRooms];
    expect(moveRailItem(order, railRooms, -1), [railHome, railRooms, railSearch]);
    expect(moveRailItem(order, railHome, -1), order);
    expect(moveRailItem(order, railRooms, 1), order);
  });

  test('the default order saves as empty, so new libraries keep their default places', () {
    expect(railOrderToSave(defaultRailOrder([_movies]), [_movies]), isEmpty);
    final moved = moveRailItem(defaultRailOrder([_movies]), railRooms, -1);
    expect(railOrderToSave(moved, [_movies]), moved);
  });

  testWidgets('the rail draws its items, and walks focus, in the saved order', (tester) async {
    final order = [railRooms, _showsId, railHome, railSearch, railWatchlist, _moviesId];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1920, 1080)),
          child: AppNavigationDrawer(
            sectionGroups: const [_movies, _shows],
            railOrder: order,
            destination: RailDestination.home,
            onSelectSection: (_) {},
            onOpenSettings: () {},
            onOpenHome: () {},
            onOpenSearch: () {},
            rooms: RoomsPanelData(
              relays: const [],
              relayHealth: const {},
              rooms: const [],
              hostedRoomIds: const {},
              onJoin: (_) {},
              onRetry: () {},
            ),
            loadServers: () async => const [],
            probeServer: (_) async => null,
            loadLibraryCount: (_) async => null,
            connectedServers: const [ReachableServer(_server, ServerReachability.local)],
            disabledServerIds: const {},
            onToggleServer: (_, _) {},
            child: const SizedBox(),
          ),
        ),
      ),
    );
    double top(IconData icon) => tester.getTopLeft(find.byIcon(icon)).dy;
    expect(top(PhosphorIconsRegular.usersThree), lessThan(top(PhosphorIconsRegular.televisionSimple)));
    expect(top(PhosphorIconsRegular.televisionSimple), lessThan(top(PhosphorIconsFill.house)));
    expect(top(PhosphorIconsRegular.bookmarkSimple), lessThan(top(PhosphorIconsRegular.filmSlate)));

    // Entering the rail lands on the current destination, Home — third in
    // this order — and Up walks to Shows above it, which in the default
    // order would be nowhere (Home is first).
    FocusNode railNode(String label) => tester
        .widget<Focus>(find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == label).first)
        .focusNode!;
    railNode('nav-rail-home').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(railNode('nav-rail-section-${_shows.key}').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(railNode('nav-rail-rooms').hasFocus, isTrue);
  });

  group('RailOrderList', () {
    Future<List<List<String>>> pumpList(WidgetTester tester, List<String> order) async {
      final changes = <List<String>>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: RailOrderList(
                order: order,
                sections: const [_movies],
                onChanged: (next) => setState(() {
                  changes.add(next);
                  order = next;
                }),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('select picks a row up, down carries it, select puts it down', (tester) async {
      final changes = await pumpList(tester, defaultRailOrder([_movies]));
      Focus.of(tester.element(find.text('Home'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Move, then OK to place'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(changes.last, [railSearch, railWatchlist, railHome, _moviesId, railRooms]);
      expect(Focus.of(tester.element(find.text('Home'))).hasFocus, isTrue, reason: 'focus travels with the row');

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Move, then OK to place'), findsNothing);

      // Put down, Down walks focus again instead of moving the row.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(changes, hasLength(2));
    });
  });
}
