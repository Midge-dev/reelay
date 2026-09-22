import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/common/click_to_type_text_field.dart';
import 'package:reelay/screens/library/library_screen.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _section = PlexSection(key: 's1', title: 'Movies', type: 'movie');
const _items = [
  PlexLibraryItem(ratingKey: '1', title: 'Alien', genres: [PlexTag(tag: 'Horror')]),
  PlexLibraryItem(ratingKey: '2', title: 'Arrival', genres: [PlexTag(tag: 'Sci-Fi')]),
];

Future<void> _pump(
  WidgetTester tester, {
  List<PlexLibraryItem> items = _items,
  Future<List<PlexCollection>> Function()? loadCollections,
}) async {
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
        loadCollections: loadCollections ?? () async => const [],
        onSelectCollection: (_) {},
      ),
    ),
  );
}

Future<void> _typeInSearchField(WidgetTester tester, String value) async {
  final field = tester.widget<ClickToTypeTextField>(find.byType(ClickToTypeTextField));
  field.focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pump();
  await tester.enterText(find.byType(EditableText), value);
  await tester.pump();
}

void main() {
  testWidgets('shows the section title, source, item count, and every item — no tabs', (tester) async {
    await _pump(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Plex · Home'), findsOneWidget);
    expect(find.text('2 titles · sorted by title'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Genres'), findsNothing, reason: 'there is no tab strip anymore');
    expect(find.text('Search'), findsNothing, reason: 'search moved into the filter row, not a tab');
  });

  testWidgets('an empty library shows the empty-state message', (tester) async {
    await _pump(tester, items: const []);

    expect(find.text('Nothing in this library yet.'), findsOneWidget);
  });

  testWidgets('the filter row always shows Genre/Decade/Added/Sort as one row', (tester) async {
    await _pump(tester);

    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Decade'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Sort · Title'), findsOneWidget);
  });

  testWidgets('opening the Genre dropdown shows every available genre with a live count', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Genre'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Horror'), findsOneWidget);
    expect(find.text('Sci-Fi'), findsOneWidget);
  });

  testWidgets('selecting a genre filters the grid, shows it inline on the chip, and updates the count', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Genre'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Horror'));
    await tester.pump();

    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
    expect(find.text('Horror'), findsOneWidget, reason: 'the chip itself now shows the applied value');
    expect(find.text('1 of 2 titles · sorted by title'), findsOneWidget);
  });

  testWidgets('Clear all resets every applied filter', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Genre'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Horror'));
    await tester.pump();
    expect(find.text('Clear all'), findsOneWidget);

    await tester.ensureVisible(find.text('Clear all'));
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();

    expect(find.text('Clear all'), findsNothing);
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('typing in the search field narrows the grid without leaving the screen', (tester) async {
    await _pump(tester);

    await _typeInSearchField(tester, 'AR');

    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Alien'), findsNothing, reason: '"Alien" does not contain "AR"');
    expect(find.text('Genre'), findsOneWidget, reason: 'the filter row is still there — this never was a separate destination');
  });

  testWidgets('switching to Collections with none loaded shows the loading then empty state', (tester) async {
    await _pump(tester, loadCollections: () async => const []);

    await tester.tap(find.text('Collections'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No collections found'), findsOneWidget);
    expect(find.text('Genre'), findsNothing, reason: 'genre/decade filter titles, not collections');
  });

  testWidgets('Collections mode renders every loaded collection with its title count', (tester) async {
    const collections = [
      PlexCollection(ratingKey: 'c1', title: 'Criterion shelf', childCount: 48),
      PlexCollection(ratingKey: 'c2', title: 'Christmas', childCount: 14),
    ];
    await _pump(tester, loadCollections: () async => collections);

    await tester.tap(find.text('Collections'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Criterion shelf'), findsOneWidget);
    expect(find.text('48 titles'), findsOneWidget);
    expect(find.text('Christmas'), findsOneWidget);
    expect(find.text('14 titles'), findsOneWidget);
    expect(find.text('2 collections · sorted by title'), findsOneWidget);
  });
}
