import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/screens/home/home_posters.dart';
import 'package:reelay/state/duplicate_fold.dart';

const _server = MediaServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', id: 'home-id');

void main() {
  group('recentlyAddedLabel', () {
    test('a season falls back to its parent (show) title', () {
      const item = MediaItem(id: '1', title: 'Season 2', kind: MediaKind.season, parentTitle: 'Fringe');
      expect(recentlyAddedLabel(item), 'Fringe');
    });

    test('a movie uses its own title', () {
      const item = MediaItem(id: '1', title: 'Arrival', kind: MediaKind.movie);
      expect(recentlyAddedLabel(item), 'Arrival');
    });
  });

  group('continueWatchingLabel', () {
    test('an episode shows show title + season/episode', () {
      const item = MediaItem(
        id: '1',
        kind: MediaKind.episode,
        title: 'Pilot',
        grandparentTitle: 'Fringe',
        parentIndex: 1,
        index: 1,
      );
      expect(continueWatchingLabel(item), 'Fringe · S1E1');
    });

    test('a movie uses its own title', () {
      const item = MediaItem(id: '1', kind: MediaKind.movie, title: 'Arrival');
      expect(continueWatchingLabel(item), 'Arrival');
    });
  });

  group('progressFraction', () {
    test('no duration returns 0', () {
      const item = MediaItem(id: '1', kind: MediaKind.movie, title: 'Arrival', viewOffset: 500);
      expect(progressFraction(item), 0);
    });

    test('clamps to 1 even if viewOffset exceeds duration', () {
      const item = MediaItem(id: '1', kind: MediaKind.movie, title: 'Arrival', duration: 1000, viewOffset: 5000);
      expect(progressFraction(item), 1);
    });

    test('computes the fraction watched', () {
      const item = MediaItem(id: '1', kind: MediaKind.movie, title: 'Arrival', duration: 1000, viewOffset: 250);
      expect(progressFraction(item), 0.25);
    });
  });

  group('WatchlistPoster', () {
    const entry = MediaItem(id: '1', title: 'Arrival');

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

    testWidgets('holding select past the long-press threshold removes it at once, not onClick (Home offers Undo)', (tester) async {
      var clicked = false;
      var removed = false;
      await pump(tester, onClick: () => clicked = true, onRemove: () => removed = true);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(clicked, isFalse, reason: "the hold's release must not also open it");
      expect(removed, isTrue);
    });
  });

  group('ContinueWatchingPoster', () {
    const item = MediaItem(id: '1', kind: MediaKind.movie, title: 'Arrival', duration: 1000, viewOffset: 250);

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

    testWidgets('holding select past the long-press threshold removes it at once, not onResume (Home offers Undo)', (tester) async {
      var resumed = false;
      var removed = false;
      await pump(tester, onResume: () => resumed = true, onRemove: () => removed = true);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(resumed, isFalse, reason: "the hold's release must not also resume it");
      expect(removed, isTrue);
    });
  });
}
