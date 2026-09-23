import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/home/home_screen.dart';
import 'package:reelay/state/duplicate_fold.dart';
import 'package:reelay/theme/scale.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');

PlexOnDeckItem _onDeck(String key) => PlexOnDeckItem(
      ratingKey: key,
      type: 'movie',
      title: 'OnDeck $key',
      duration: 1000,
      viewOffset: 250,
      summary: 'A long synopsis that wraps across more than one line of the hero column so the '
          'intrinsic height calculation actually has several lines of body copy to account for.',
    );

void main() {
  // The Shield's real geometry: a 960x540 logical canvas, so the design's
  // 1080 du height maps to factor 0.5, times the 130% UI Size default.
  for (final uiScale in [1.0, 1.3, 1.5]) {
    testWidgets('Home lays out without overflow at ${(uiScale * 100).round()}% on a 960x540 canvas', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FoldedWork<T> folded<T>(T v) => FoldedWork(null, [Sourced(v, _server, ServerReachability.local)]);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(960, 540)),
            child: AppScale(
              factor: 540 / 1080 * uiScale,
              child: HomeScreen(
                servers: const [ReachableServer(_server, ServerReachability.local)],
                onDeck: [for (final k in ['1', '2', '3']) folded(_onDeck(k))],
                recentlyAdded: [folded(const PlexLibraryItem(ratingKey: '9', title: 'Arrival', type: 'movie', year: 2016))],
                onEndSession: (_) async => true,
                onSelectRoom: (_) {},
                onOpenRooms: () {},
                onResume: (_) {},
                onRemove: (_) {},
                onSelectWatchlistItem: (_) {},
                onRemoveFromWatchlist: (_) {},
                onSelectRecentlyAdded: (_) {},
                onSelectRecentActivity: (_) {},
                onSelectSuggestion: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
