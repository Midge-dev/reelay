import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/collection_detail_screen.dart';
import 'package:reelay/screens/library/person_filmography_screen.dart';
import 'package:reelay/screens/library/poster_card.dart';

/// PosterCard's title label sits below the clickable card, as a plain
/// (non-focusable) sibling — same shape as Kotlin's CardContainer. Tap the
/// PosterCard ancestor rather than the label text itself.
Finder _posterCardFor(String title) => find.ancestor(of: find.text(title), matching: find.byType(PosterCard));

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(size: Size(1920, 1080)), child: child),
    ),
  );
}

void main() {
  group('CollectionDetailScreen', () {
    const items = [
      PlexLibraryItem(ratingKey: '1', title: 'Movie A'),
      PlexLibraryItem(ratingKey: '2', title: 'Movie B'),
    ];
    const collection = PlexCollection(ratingKey: 'c1', title: 'Action Pack');

    testWidgets('shows the collection title, item count, and every item title', (tester) async {
      await _pump(
        tester,
        CollectionDetailScreen(server: _server, collection: collection, items: items, onSelectItem: (_) {}, onBack: () {}),
      );

      expect(find.text('Action Pack'), findsOneWidget);
      expect(find.text('2 titles'), findsOneWidget);
      expect(find.text('Movie A'), findsOneWidget);
      expect(find.text('Movie B'), findsOneWidget);
    });

    testWidgets('shows a singular count for one item', (tester) async {
      await _pump(
        tester,
        CollectionDetailScreen(server: _server, collection: collection, items: [items[0]], onSelectItem: (_) {}, onBack: () {}),
      );

      expect(find.text('1 title'), findsOneWidget);
    });

    testWidgets('shows an empty-state message with no items', (tester) async {
      await _pump(
        tester,
        CollectionDetailScreen(server: _server, collection: collection, items: const [], onSelectItem: (_) {}, onBack: () {}),
      );

      expect(find.text('No titles found in this collection.'), findsOneWidget);
    });

    testWidgets('tapping an item invokes onSelectItem with that item', (tester) async {
      PlexLibraryItem? selected;
      await _pump(
        tester,
        CollectionDetailScreen(server: _server, collection: collection, items: items, onSelectItem: (i) => selected = i, onBack: () {}),
      );

      await tester.tap(_posterCardFor('Movie B'));
      await tester.pump();

      expect(selected?.ratingKey, '2');
    });
  });

  group('PersonFilmographyScreen', () {
    testWidgets('shows the person name, title count, and an initial fallback avatar', (tester) async {
      await _pump(
        tester,
        PersonFilmographyScreen(
          server: _server,
          personName: 'Denis Villeneuve',
          items: const [PlexLibraryItem(ratingKey: '1', title: 'Dune')],
          onSelectItem: (_) {},
          onBack: () {},
        ),
      );

      expect(find.text('Denis Villeneuve'), findsOneWidget);
      expect(find.text('1 title in your library'), findsOneWidget);
      expect(find.text('D'), findsOneWidget, reason: 'no thumb -> falls back to the first letter of the name');
      expect(find.text('Dune'), findsOneWidget);
    });
  });
}
