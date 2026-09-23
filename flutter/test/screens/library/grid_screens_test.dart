import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/library/collection_detail_screen.dart';
import 'package:reelay/screens/library/person_filmography_screen.dart';
import 'package:reelay/screens/library/poster_card.dart';
import 'package:reelay/state/duplicate_fold.dart';
import 'package:reelay/state/person_credits.dart';

/// PosterCard's title label sits below the clickable card, as a plain
/// (non-focusable) sibling. Tap the
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

  group('PersonFilmographyScreen (03c)', () {
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1920, 1080);
      view.devicePixelRatio = 1.0;
    });
    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
    const attic = PlexServer(name: 'Attic', baseUrl: 'http://a:32400', accessToken: 't', machineIdentifier: 'attic');
    const loft = PlexServer(name: 'Loft', baseUrl: 'http://l:32400', accessToken: 't', machineIdentifier: 'loft');
    const servers = [
      ReachableServer(attic, ServerReachability.local),
      ReachableServer(loft, ServerReachability.local),
    ];
    FoldedWork<PlexLibraryItem> work(PlexServer server, String key, String title, int year) {
      final item = PlexLibraryItem(ratingKey: key, title: title, year: year, type: 'movie', guid: 'plex://movie/$key');
      return FoldedWork(item.guid, [Sourced(item, server, ServerReachability.local)]);
    }

    final works = [
      work(attic, '1', 'Dune', 2021),
      work(loft, '2', 'Arrival', 2016),
      work(attic, '3', 'Sicario', 2015),
    ];
    const credits = {
      '1': PersonCredit(character: 'Paul Atreides', acted: true),
      '2': PersonCredit(directed: true),
      '3': PersonCredit(character: 'Alejandro', acted: true),
    };

    Future<void> pumpPerson(WidgetTester tester, {ValueChanged<FoldedWork<PlexLibraryItem>>? onSelect}) async {
      await _pump(
        tester,
        PersonFilmographyScreen(
          servers: servers,
          originServer: attic,
          person: const PlexPerson(id: 7, tag: 'Denis Villeneuve'),
          loadWorks: () async => works,
          loadCredit: (w) async => credits[w.primary.value.ratingKey],
          onSelectItem: onSelect ?? (_) {},
          onBack: () {},
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('names the person, how many titles and which servers', (tester) async {
      await pumpPerson(tester);
      expect(find.text('Denis Villeneuve'), findsOneWidget);
      expect(find.text('3 titles on Attic and Loft'), findsOneWidget);
      expect(find.text('D'), findsOneWidget, reason: 'no thumb -> first letter of the name');
    });

    testWidgets('captions carry the role, not just the year', (tester) async {
      await pumpPerson(tester);
      expect(find.text('Paul Atreides · 2021'), findsOneWidget);
      expect(find.text('Director · 2016'), findsOneWidget);
    });

    testWidgets('chips split the same list by what they did', (tester) async {
      await pumpPerson(tester);
      expect(find.text('Everything · 3'), findsOneWidget);
      expect(find.text('Appears in · 2'), findsOneWidget);
      expect(find.text('Directed · 1'), findsOneWidget);

      await tester.tap(find.text('Directed · 1'));
      await tester.pump();
      expect(find.text('Arrival'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
    });

    testWidgets('someone who only acted gets no chips', (tester) async {
      await _pump(
        tester,
        PersonFilmographyScreen(
          servers: servers,
          originServer: attic,
          person: const PlexPerson(tag: 'Actor'),
          loadWorks: () async => [works[0], works[2]],
          loadCredit: (w) async => credits[w.primary.value.ratingKey],
          onSelectItem: (_) {},
          onBack: () {},
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Everything'), findsNothing);
      expect(find.text('2 titles on Attic'), findsOneWidget);
    });

    testWidgets('selecting a title hands over the whole folded work', (tester) async {
      FoldedWork<PlexLibraryItem>? selected;
      await pumpPerson(tester, onSelect: (w) => selected = w);
      await tester.tap(_posterCardFor('Dune'));
      await tester.pump();
      expect(selected?.primary.value.ratingKey, '1');
    });
  });
}
