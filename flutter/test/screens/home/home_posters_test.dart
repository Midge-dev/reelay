import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/home/home_posters.dart';
import 'package:reelay/state/duplicate_fold.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');

void main() {
  group('recentlyAddedLabel', () {
    test('a season falls back to its parent (show) title', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'Season 2', type: 'season', parentTitle: 'Fringe');
      expect(recentlyAddedLabel(item), 'Fringe');
    });

    test('a movie uses its own title', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'Arrival', type: 'movie');
      expect(recentlyAddedLabel(item), 'Arrival');
    });
  });

  group('continueWatchingLabel', () {
    test('an episode shows show title + season/episode', () {
      const item = PlexOnDeckItem(
        ratingKey: '1',
        type: 'episode',
        title: 'Pilot',
        grandparentTitle: 'Fringe',
        parentIndex: 1,
        index: 1,
      );
      expect(continueWatchingLabel(item), 'Fringe · S1E1');
    });

    test('a movie uses its own title', () {
      const item = PlexOnDeckItem(ratingKey: '1', type: 'movie', title: 'Arrival');
      expect(continueWatchingLabel(item), 'Arrival');
    });
  });

  group('progressFraction', () {
    test('no duration returns 0', () {
      const item = PlexOnDeckItem(ratingKey: '1', type: 'movie', title: 'Arrival', viewOffset: 500);
      expect(progressFraction(item), 0);
    });

    test('clamps to 1 even if viewOffset exceeds duration', () {
      const item = PlexOnDeckItem(ratingKey: '1', type: 'movie', title: 'Arrival', duration: 1000, viewOffset: 5000);
      expect(progressFraction(item), 1);
    });

    test('computes the fraction watched', () {
      const item = PlexOnDeckItem(ratingKey: '1', type: 'movie', title: 'Arrival', duration: 1000, viewOffset: 250);
      expect(progressFraction(item), 0.25);
    });
  });

  group('WatchlistPoster', () {
    const entry = PlexWatchlistItem(ratingKey: '1', title: 'Arrival');

    Future<void> pump(WidgetTester tester, {VoidCallback? onClick, VoidCallback? onRemove}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: WatchlistPoster(
              server: _server,
              entry: entry,
              onClick: onClick ?? () {},
              onRemove: onRemove ?? () {},
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the title', (tester) async {
      await pump(tester);
      expect(find.text('Arrival'), findsOneWidget);
    });

    testWidgets('tapping invokes onClick', (tester) async {
      var clicked = false;
      await pump(tester, onClick: () => clicked = true);

      await tester.tap(find.byType(WatchlistPoster));
      await tester.pump();

      expect(clicked, isTrue);
    });

    testWidgets('holding select past the long-press threshold opens the remove confirm, not onClick', (tester) async {
      var clicked = false;
      var removed = false;
      await pump(tester, onClick: () => clicked = true, onRemove: () => removed = true);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));

      expect(clicked, isFalse);
      expect(find.text('Remove Arrival from your watchlist?'), findsOneWidget);

      // The physical select key is still held when the overlay grabs focus
      // onto Remove, so its eventual key-up lands there as a bare
      // KeyUpEvent — which FocusableSurface reads as a click. That's the
      // documented cross-widget checklist #3 hazard: this first "click" is
      // absorbed as the overlay's arming press, not a second real one.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(removed, isFalse, reason: 'the swallowed key-up only arms the guard, it must not confirm by itself');
      expect(find.text('Remove Arrival from your watchlist?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pump();

      expect(removed, isTrue);
    });
  });

  group('ContinueWatchingPoster', () {
    const item = PlexOnDeckItem(ratingKey: '1', type: 'movie', title: 'Arrival', duration: 1000, viewOffset: 250);

    Future<void> pump(WidgetTester tester, {VoidCallback? onResume, VoidCallback? onRemove}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ContinueWatchingPoster(
              item: FoldedWork(item.guid, [Sourced(item, _server, ServerReachability.local)]),
              onResume: onResume ?? () {},
              onRemove: onRemove ?? () {},
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the title', (tester) async {
      await pump(tester);
      expect(find.text('Arrival'), findsOneWidget);
    });

    testWidgets('tapping invokes onResume', (tester) async {
      var resumed = false;
      await pump(tester, onResume: () => resumed = true);

      await tester.tap(find.byType(ContinueWatchingPoster));
      await tester.pump();

      expect(resumed, isTrue);
    });

    testWidgets('holding select past the long-press threshold opens the remove confirm, not onResume', (tester) async {
      var resumed = false;
      var removed = false;
      await pump(tester, onResume: () => resumed = true, onRemove: () => removed = true);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));

      expect(resumed, isFalse);
      expect(find.text('Remove from Continue Watching?'), findsOneWidget);

      // See the matching WatchlistPoster test for why the trailing key-up
      // (still landing on the newly-focused Remove button) only arms the
      // guard rather than confirming outright.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(removed, isFalse);
      expect(find.text('Remove from Continue Watching?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pump();

      expect(removed, isTrue);
    });
  });
}
