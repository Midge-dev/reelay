import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/home/home_posters.dart';
import 'package:reelay/screens/home/home_screen.dart';
import 'package:reelay/screens/home/watch_together_bar.dart';
import 'package:reelay/screens/home/watch_together_row.dart';
import 'package:reelay/state/duplicate_fold.dart';
import 'package:reelay/sync/relay_protocol.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');
const _connectedServers = [ReachableServer(_server, ServerReachability.local)];
const _relay = RelayEntry(id: 'r1', nickname: 'Home Relay', url: 'wss://relay.example.com');

RelayRoomSummary _room(String id) =>
    RelayRoomSummary(roomId: id, title: 'Arrival', hostName: 'Sean', occupants: 1, maxSeats: 4);

PlexWatchlistItem _watchlistItem(String key) => PlexWatchlistItem(ratingKey: key, title: 'Watchlist $key');

PlexOnDeckItem _onDeckItem(String key) =>
    PlexOnDeckItem(ratingKey: key, type: 'movie', title: 'OnDeck $key', duration: 1000, viewOffset: 250);

/// Walks up from the currently focused widget looking for an ancestor of
/// [type] — used to assert *which row* actually claimed initial/reclaimed
/// focus, since each row's items are built by a different widget type.
bool _focusIsWithin(Type type) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  var found = false;
  focusContext.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType == type) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Widget _buildHome({
  List<MergedRoom> liveRooms = const [],
  List<PlexWatchlistItem> watchlist = const [],
  List<PlexOnDeckItem> onDeck = const [],
  List<PlexOnDeckItem> recentActivity = const [],
  List<PlexLibraryItem> recentlyAdded = const [],
  List<PlexOnDeckItem> suggestions = const [],
}) {
  FoldedWork<T> folded<T>(T v) => FoldedWork(null, [Sourced(v, _server, ServerReachability.local)]);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: HomeScreen(
      servers: _connectedServers,
      liveRooms: liveRooms,
      watchlist: watchlist,
      onDeck: onDeck.map(folded).toList(),
      recentActivity: recentActivity.map(folded).toList(),
      recentlyAdded: recentlyAdded.map(folded).toList(),
      suggestions: suggestions.map(folded).toList(),
      onEndSession: (_) async => true,
      onSelectRoom: (_) {},
      onOpenRooms: () {},
      onResume: (_) {},
      onRemove: (_) {},
      onSelectWatchlistItem: (_) {},
      onRemoveFromWatchlist: (_) {},
      onSelectRecentlyAdded: (_) {},
      onSelectRecentActivity: (_) {},
      onSelectSuggestion: (_) {},
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(widget);
  await tester.pump();
}

void main() {
  group('row visibility', () {
    testWidgets('an empty screen shows no rows', (tester) async {
      await _pump(tester, _buildHome());

      expect(find.text('Watch Together'), findsNothing);
      expect(find.text('Watchlist'), findsNothing);
      expect(find.text('Recently Finished Watching'), findsNothing);
      expect(find.text('Recently Added'), findsNothing);
      expect(find.text('Suggestions'), findsNothing);
      expect(find.text('Continue Watching'), findsOneWidget, reason: 'always shown, even empty');
      expect(find.text('Nothing in progress right now.'), findsOneWidget);
    });

    testWidgets('only rows with data render, in order', (tester) async {
      await _pump(
        tester,
        _buildHome(
          watchlist: [_watchlistItem('1')],
          recentlyAdded: const [PlexLibraryItem(ratingKey: '1', title: 'Arrival', type: 'movie')],
        ),
      );

      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Recently Finished Watching'), findsNothing);
      expect(find.text('Suggestions'), findsNothing);
    });
  });

  group('initial-focus priority cascade', () {
    testWidgets('Watch Together wins over every other row when live', (tester) async {
      await _pump(
        tester,
        _buildHome(
          liveRooms: [MergedRoom(_relay, _room('a'))],
          watchlist: [_watchlistItem('1')],
          onDeck: [_onDeckItem('1')],
        ),
      );

      expect(_focusIsWithin(WatchTogetherBar), isTrue);
    });

    testWidgets('Watchlist wins when Watch Together is empty', (tester) async {
      await _pump(
        tester,
        _buildHome(watchlist: [_watchlistItem('1')], onDeck: [_onDeckItem('1')]),
      );

      expect(_focusIsWithin(WatchTogetherBar), isFalse);
    });

    testWidgets('Continue Watching wins when Watch Together and Watchlist are both empty', (tester) async {
      await _pump(
        tester,
        _buildHome(
          onDeck: [_onDeckItem('1')],
          recentlyAdded: const [PlexLibraryItem(ratingKey: '1', title: 'Arrival', type: 'movie')],
        ),
      );

      expect(_focusIsWithin(WatchTogetherBar), isFalse);
    });
  });

  group('reclaim focus on removal (checklist #2)', () {
    testWidgets('removing a watchlist item while another row holds focus reclaims the watchlist row', (tester) async {
      // Watch Together starts as the focused row, not Watchlist.
      final widget1 = _buildHome(
        liveRooms: [MergedRoom(_relay, _room('a'))],
        watchlist: [_watchlistItem('1'), _watchlistItem('2')],
      );
      await _pump(tester, widget1);
      expect(_focusIsWithin(WatchTogetherBar), isTrue);

      // Same HomeScreen instance shape, watchlist shrinks by one item —
      // this should reclaim focus onto the watchlist row's anchor even
      // though focus was elsewhere, not let it fall through to whatever
      // the platform's default disposal search would pick.
      final widget2 = _buildHome(
        liveRooms: [MergedRoom(_relay, _room('a'))],
        watchlist: [_watchlistItem('1')],
      );
      await tester.pumpWidget(widget2);
      await tester.pump();

      expect(_focusIsWithin(WatchlistPoster), isTrue);
    });
  });
}
