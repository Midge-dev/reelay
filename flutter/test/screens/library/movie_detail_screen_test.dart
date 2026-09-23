import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/theme/phosphor_icons.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/library/movie_detail_screen.dart';
import 'package:reelay/screens/library/source_picker_dialog.dart';
import 'package:reelay/state/copy_facts.dart';
import 'package:reelay/state/duplicate_fold.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');
const _movie = PlexLibraryItem(ratingKey: '1', title: 'Arrival', year: 2016, summary: 'A linguist deciphers alien contact.');

Future<void> _pump(
  WidgetTester tester, {
  void Function(String, int)? onPlay,
  int? resumeAtMs,
  bool Function(String?)? isOnWatchlist,
  FoldedWork<PlexLibraryItem>? work,
  void Function(Sourced<PlexLibraryItem>, int)? onSwitchSource,
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
        onSwitchSource: onSwitchSource ?? (_, _) {},
        loadCopyFacts: (copy) async => CopyFacts(
          picture: copy.server.name == 'Home' ? '4K HDR' : '1080p',
          audio: 'AAC 5.1',
          file: 'HEVC 34.2 GB',
          directPlay: copy.server.name == 'Home',
          pictureRank: copy.server.name == 'Home' ? 2160 : 1080,
        ),
        resumeAtMs: resumeAtMs,
        onBack: () {},
        onPlay: onPlay ?? (_, _) {},
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
    await _pump(tester, onPlay: (key, _) => played = key);
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

      expect(find.text('${_movie.title} is on two of your servers'), findsOneWidget);
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
      await _pump(tester, work: work, onSwitchSource: (s, _) => switched = s);
      await tester.pump();

      await tester.tap(find.text('2 copies'));
      await tester.pump();
      await tester.tap(find.text('Loft'));
      await tester.pump();

      expect(switched?.server.name, 'Loft');
      expect(find.text('Back closes and keeps the chosen source'), findsNothing);
    });
  });

  group('03d rows', () {
    final work = FoldedWork(_movie.guid, [
      Sourced(_movie, _server, ServerReachability.local),
      Sourced(_movie, _otherServer, ServerReachability.local),
    ]);
    Finder inPicker(String text) => find.descendant(of: find.byType(SourcePickerDialog), matching: find.text(text));

    testWidgets('each row states what the file is and what playing it costs', (tester) async {
      await _pump(tester, work: work);
      await tester.pump();
      await tester.tap(find.text('2 copies'));
      await tester.pump();
      await tester.pump();

      expect(inPicker('Plex · local · HEVC 34.2 GB'), findsNWidgets(2));
      expect(inPicker('4K HDR'), findsOneWidget);
      expect(inPicker('Direct play'), findsOneWidget);
      expect(inPicker('Will transcode'), findsOneWidget);
      expect(inPicker('Lower quality'), findsOneWidget);
    });

    testWidgets('progress is kept against the title: a switch carries it', (tester) async {
      int? carried;
      await _pump(tester, work: work, resumeAtMs: 46 * 60000 + 12000, onSwitchSource: (_, at) => carried = at);
      await tester.pump();
      await tester.tap(find.text('2 copies'));
      await tester.pump();
      await tester.pump();

      expect(
        inPicker('You are 46:12 in. That is kept against the title, so any source you pick resumes there.'),
        findsOneWidget,
      );
      await tester.tap(inPicker('Loft'));
      await tester.pump();
      expect(carried, 46 * 60000 + 12000);
    });
  });
}
