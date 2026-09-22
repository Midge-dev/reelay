import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/movie_detail_screen.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _movie = PlexLibraryItem(ratingKey: '1', title: 'Arrival', year: 2016, summary: 'A linguist deciphers alien contact.');

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<String>? onPlay,
  bool Function(String?)? isOnWatchlist,
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
        onBack: () {},
        onPlay: onPlay ?? (_) {},
        onWatchTogether: (_) {},
        onRestartSolo: (_) {},
        isOnWatchlist: isOnWatchlist ?? (_) => false,
        onToggleWatchlist: (_) {},
        loadDetail: () async => null,
        loadRelatedHubs: () async => const [],
        loadByActor: (_) async => const [],
        onSelectRelated: (_) {},
        onSelectPerson: (_) {},
      ),
    ),
  );
}

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

    expect(find.text('+'), findsOneWidget, reason: 'not on watchlist -> + button');
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

    expect(find.text('✓'), findsOneWidget);
    expect(find.text('+'), findsNothing);
  });
}
