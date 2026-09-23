import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/theme/phosphor_icons.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/library/movie_detail_screen.dart';
import 'package:reelay/screens/library/source_picker_dialog.dart';
import 'package:reelay/state/duplicate_fold.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');
const _movie = PlexLibraryItem(ratingKey: '1', title: 'Arrival', year: 2016, summary: 'A linguist deciphers alien contact.');

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<String>? onPlay,
  bool Function(String?)? isOnWatchlist,
  FoldedWork<PlexLibraryItem>? work,
  ValueChanged<Sourced<PlexLibraryItem>>? onSwitchSource,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MovieDetailScreen(
        server: _server,
        movie: _movie,
        work: work ?? FoldedWork(_movie.guid, [Sourced(_movie, _server, ServerReachability.local)]),
        onSwitchSource: onSwitchSource ?? (_) {},
        onBack: () {},
        onPlay: onPlay ?? (_) {},
        onWatchTogether: (_) {},
        onRestartSolo: (_) {},
        isOnWatchlist: isOnWatchlist ?? (_) => false,
        onToggleWatchlist: (_) {},
        loadDetail: () async => null,
        loadRelatedHubs: () async => const [],
        onSelectRelated: (_) {},
        onSelectPerson: (_) {},
      ),
    ),
  );
}

const _otherServer = PlexServer(name: 'Loft', baseUrl: 'http://192.168.1.9:32400', accessToken: 'tok2', machineIdentifier: 'loft-id');

void main() {
  testWidgets('shows the movie title, year, and summary in the hero', (tester) async {
    await _pump(tester);
    await tester.pump();

    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('2016'), findsOneWidget);
    expect(find.text('A linguist deciphers alien contact.'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('shows a Watchlist button', (tester) async {
    await _pump(tester);
    await tester.pump();

    expect(find.byIcon(PhosphorIconsRegular.plus), findsOneWidget, reason: 'not on watchlist -> plus button');
  });

  testWidgets('tapping Play invokes onPlay with the movie ratingKey', (tester) async {
    String? played;
    await _pump(tester, onPlay: (key) => played = key);
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();

    expect(played, '1');
  });

  testWidgets('an item already on the watchlist shows a checkmark', (tester) async {
    await _pump(tester, isOnWatchlist: (_) => true);
    await tester.pump();

    expect(find.byIcon(PhosphorIconsRegular.check), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.plus), findsNothing);
  });

  group('source picker', () {
    testWidgets('a single-copy work shows no copy count and is not clickable', (tester) async {
      await _pump(tester);
      await tester.pump();

      expect(find.textContaining('copies'), findsNothing);
    });

    testWidgets('a multi-copy work shows the copy count and opens the picker on tap', (tester) async {
      final work = FoldedWork(_movie.guid, [
        Sourced(_movie, _server, ServerReachability.local),
        Sourced(_movie, _otherServer, ServerReachability.relayed),
      ]);
      await _pump(tester, work: work);
      await tester.pump();

      expect(find.text('2 copies'), findsOneWidget);

      await tester.tap(find.text('2 copies'));
      await tester.pump();

      expect(find.text('${_movie.title} is on 2 of your servers'), findsOneWidget);
      // "Home" is also in the page's own "Playing from" chip.
      Finder inPicker(String text) => find.descendant(of: find.byType(SourcePickerDialog), matching: find.text(text));
      expect(inPicker('Home'), findsOneWidget);
      expect(inPicker('Loft'), findsOneWidget);
      expect(inPicker('Chosen'), findsOneWidget);
    });

    testWidgets('selecting a reachable alternate invokes onSwitchSource and closes the dialog', (tester) async {
      Sourced<PlexLibraryItem>? switched;
      final work = FoldedWork(_movie.guid, [
        Sourced(_movie, _server, ServerReachability.local),
        Sourced(_movie, _otherServer, ServerReachability.relayed),
      ]);
      await _pump(tester, work: work, onSwitchSource: (s) => switched = s);
      await tester.pump();

      await tester.tap(find.text('2 copies'));
      await tester.pump();
      await tester.tap(find.text('Loft'));
      await tester.pump();

      expect(switched?.server.name, 'Loft');
      expect(find.text('Back closes and keeps the current source'), findsNothing);
    });
  });
}
