import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/library_screen.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _section = PlexSection(key: 's1', title: 'Movies', type: 'movie');
const _items = [
  PlexLibraryItem(ratingKey: '1', title: 'Alien', genres: [PlexTag(tag: 'Horror')]),
  PlexLibraryItem(ratingKey: '2', title: 'Arrival', genres: [PlexTag(tag: 'Sci-Fi')]),
];

Future<void> _pump(WidgetTester tester, {List<PlexLibraryItem> items = _items}) async {
  // The test surface defaults to a much smaller logical size than a real
  // TV; wrapping in MediaQuery alone is cosmetic and doesn't affect actual
  // layout constraints, so the view itself needs resizing.
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: LibraryScreen(
        server: _server,
        selectedSection: _section,
        items: items,
        onSelectItem: (_) {},
        loadCollections: () async => const [],
        onSelectCollection: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('All tab shows the section title, item count, and every item', (tester) async {
    await _pump(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('2 titles · A–Z'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('an empty library shows the empty-state message on the All tab', (tester) async {
    await _pump(tester, items: const []);

    expect(find.text('Nothing in this library yet.'), findsOneWidget);
  });

  testWidgets('switching to the Search tab shows the keyboard and typing filters results', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(find.text('Type a title…'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('R'));
    await tester.pump();

    expect(find.text('AR'), findsOneWidget, reason: 'the query box should show what was typed');
    expect(find.textContaining('titles for "AR"'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Alien'), findsNothing, reason: '"Alien" does not contain "AR"');
  });

  testWidgets('switching to the Genres tab shows every available genre as a filter row', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Genres'));
    await tester.pump();

    expect(find.text('Horror'), findsOneWidget);
    expect(find.text('Sci-Fi'), findsOneWidget);
  });

  testWidgets('selecting a genre filters the grid and shows an applied chip', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Genres'));
    await tester.pump();
    await tester.tap(find.text('Horror'));
    await tester.pump();

    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
    expect(find.text('1 titles · Sort: Title'), findsOneWidget);
  });

  testWidgets('switching to the Collections tab with none loaded shows the empty state', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Collections'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No collections found'), findsOneWidget);
  });
}
