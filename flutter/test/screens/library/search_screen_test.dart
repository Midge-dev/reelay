import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/screens/library/search_screen.dart';
import 'package:reelay/state/duplicate_fold.dart';

const _server = PlexServer(name: 'Attic', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'm1');
const _connectedServers = [ReachableServer(_server, ServerReachability.local)];
const _debounceSettle = Duration(milliseconds: 400);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<PlexOnDeckItem>> Function(String query) search,
  ValueChanged<PlexOnDeckItem>? onSelectResult,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SearchScreen(
        servers: _connectedServers,
        search: (q) async {
          final results = await search(q);
          return results.map((i) => Sourced(i, _server, ServerReachability.local)).toList();
        },
        onSelectResult: (item) => (onSelectResult ?? (_) {})(item.value),
        onBack: () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the placeholder and no results panel with an empty query', (tester) async {
    await _pump(tester, search: (_) async => const []);

    expect(find.text('Type a title…'), findsOneWidget);
    expect(find.text('No matches for "".'), findsNothing);
  });

  testWidgets('typing a letter queries and shows grouped results', (tester) async {
    String? queried;
    await _pump(
      tester,
      search: (q) async {
        queried = q;
        return const [
          PlexOnDeckItem(ratingKey: 's1', type: 'show', title: 'Borderland'),
          PlexOnDeckItem(ratingKey: 'm1', type: 'movie', title: 'Bordeaux'),
        ];
      },
    );

    await tester.tap(find.text('B'));
    await tester.pump(_debounceSettle);
    await tester.pump();

    expect(queried, 'B');
    expect(find.text('SERIES'), findsOneWidget);
    expect(find.text('MOVIES'), findsOneWidget);
    expect(find.text('Borderland'), findsOneWidget);
    expect(find.text('Bordeaux'), findsOneWidget);
    expect(find.text('2 results'), findsOneWidget);
  });

  testWidgets('shows a no-matches message when the search comes back empty', (tester) async {
    await _pump(tester, search: (_) async => const []);

    await tester.tap(find.text('B'));
    await tester.pump(_debounceSettle);
    await tester.pump();

    expect(find.text('No matches for "B".'), findsOneWidget);
  });

  testWidgets('tapping a result invokes onSelectResult', (tester) async {
    PlexOnDeckItem? selected;
    await _pump(
      tester,
      search: (_) async => const [PlexOnDeckItem(ratingKey: 'm1', type: 'movie', title: 'Bordeaux')],
      onSelectResult: (item) => selected = item,
    );

    await tester.tap(find.text('B'));
    await tester.pump(_debounceSettle);
    await tester.pump();

    await tester.tap(find.byType(AppCard));
    await tester.pump();

    expect(selected?.ratingKey, 'm1');
  });

  testWidgets('CLEAR resets the query and clears results', (tester) async {
    await _pump(
      tester,
      search: (_) async => const [PlexOnDeckItem(ratingKey: 'm1', type: 'movie', title: 'Bordeaux')],
    );

    await tester.tap(find.text('B'));
    await tester.pump(_debounceSettle);
    await tester.pump();
    expect(find.text('Bordeaux'), findsOneWidget);

    await tester.tap(find.text('CLEAR'));
    await tester.pump();

    expect(find.text('Type a title…'), findsOneWidget);
    expect(find.text('Bordeaux'), findsNothing);
  });
}
