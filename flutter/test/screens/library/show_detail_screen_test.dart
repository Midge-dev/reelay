import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/screens/library/show_detail_screen.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _show = PlexLibraryItem(ratingKey: 'show1', title: 'The Long Field', year: 2022, summary: 'Three generations work the same stretch of borderland.');

const _seasons = [
  PlexSeason(ratingKey: 's1', title: 'Season 1', index: 1),
  PlexSeason(ratingKey: 's2', title: 'Season 2', index: 2),
];

const _season1Episodes = [
  PlexEpisode(ratingKey: 'e1', title: 'Fencelines', index: 1, parentIndex: 1, duration: 3000000),
  PlexEpisode(ratingKey: 'e2', title: 'The Dry Year', index: 2, parentIndex: 1, duration: 3000000),
];
const _season2Episodes = [
  PlexEpisode(ratingKey: 'e3', title: 'Salt in the Well', index: 1, parentIndex: 2, duration: 3000000),
];

Future<void> _pump(
  WidgetTester tester, {
  PlexOnDeckItem? nextEpisode,
  ValueChanged<PlexEpisode>? onSelectEpisode,
  ValueChanged<String>? onPlay,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ShowDetailScreen(
        server: _server,
        show: _show,
        onBack: () {},
        onPlay: onPlay ?? (_) {},
        onWatchTogether: (_) {},
        onSelectEpisode: onSelectEpisode ?? (_) {},
        isOnWatchlist: (_) => false,
        onToggleWatchlist: (_) {},
        resolveNextEpisode: () async => nextEpisode,
        loadDetail: () async => null,
        loadSeasons: () async => _seasons,
        loadEpisodes: (seasonRatingKey) async => seasonRatingKey == 's1' ? _season1Episodes : _season2Episodes,
      ),
    ),
  );
  // Two microtask hops: resolveNextEpisode+loadDetail+loadSeasons, then
  // the follow-up loadEpisodes call for the picked season.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the show title, meta, and summary in the hero', (tester) async {
    await _pump(tester);

    expect(find.text('The Long Field'), findsOneWidget);
    expect(find.textContaining('2022'), findsOneWidget);
    expect(find.textContaining('2 seasons'), findsOneWidget);
    expect(find.text('Three generations work the same stretch of borderland.'), findsOneWidget);
  });

  testWidgets('shows every season as a chip and defaults to season 1 with no progress', (tester) async {
    await _pump(tester);

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('Fencelines'), findsOneWidget);
    expect(find.text('The Dry Year'), findsOneWidget);
  });

  testWidgets('the play button targets the next unwatched episode when there is one', (tester) async {
    await _pump(
      tester,
      nextEpisode: const PlexOnDeckItem(ratingKey: 'e3', type: 'episode', title: 'Salt in the Well', parentIndex: 2, index: 1),
    );

    expect(find.text('Play S2E1'), findsOneWidget);
    // The season containing the next-unwatched episode is selected on arrival.
    expect(find.text('Salt in the Well'), findsOneWidget);
  });

  testWidgets('tapping a season chip loads and shows that season episodes', (tester) async {
    await _pump(tester);
    expect(find.text('Fencelines'), findsOneWidget);

    await tester.ensureVisible(find.text('Season 2'));
    await tester.tap(find.text('Season 2'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Fencelines'), findsNothing);
    expect(find.text('Salt in the Well'), findsOneWidget);
  });

  testWidgets('tapping an episode invokes onSelectEpisode', (tester) async {
    PlexEpisode? selected;
    await _pump(tester, onSelectEpisode: (e) => selected = e);

    await tester.ensureVisible(find.byType(AppCard).first);
    await tester.tap(find.byType(AppCard).first);
    await tester.pump();

    expect(selected?.ratingKey, 'e1');
  });
}
