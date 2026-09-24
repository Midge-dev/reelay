import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/focus/back_handler.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/navigation/app_navigation_drawer.dart';
import 'package:reelay/screens/navigation/server_switcher_panel.dart';

const _server = PlexServer(
  name: 'Home',
  baseUrl: 'http://192.168.1.5:32400',
  accessToken: 'tok',
  machineIdentifier: 'home-id',
);

Widget _app({
  required List<PlexResource> resources,
  VoidCallback? onPageBack,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (c, _, _) => builder(c),
  ),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1920, 1080)),
    // Library, Search, Watchlist: the page's own Back wraps the rail too.
    child: BackHandler(
      onBack: onPageBack ?? () {},
      child: AppNavigationDrawer(
        sectionGroups: const [],
        destination: RailDestination.home,
        onSelectSection: (_) {},
        onOpenSettings: () {},
        onOpenHome: () {},
        onOpenSearch: () {},
        loadServers: () async => resources,
        probeServer: (_) async => null,
        loadLibraryCount: (_) async => null,
        connectedServers: const [
          ReachableServer(_server, ServerReachability.local),
        ],
        disabledServerIds: const {},
        onToggleServer: (_, _) {},
        // A focusable card in the screen, right of the panel's edge.
        child: Align(
          alignment: Alignment.topRight,
          child: Focus(child: const SizedBox(width: 200, height: 200)),
        ),
      ),
    ),
  ),
);

Future<void> _openPanel(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final avatar = find.byWidgetPredicate(
    (w) => w is Focus && w.focusNode?.debugLabel == 'nav-rail-avatar',
  );
  await tester.tap(avatar.first);
  await tester.pumpAndSettle();
  expect(find.byType(ServerSwitcherPanel), findsOneWidget);
}

void main() {
  testWidgets('Back with focus on a server row closes the panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        resources: const [
          PlexResource(name: 'Home', owned: true, machineIdentifier: 'home-id'),
        ],
      ),
    );
    await _openPanel(tester);
    debugPrint('focus: ${FocusManager.instance.primaryFocus}');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ServerSwitcherPanel), findsNothing);
  });

  for (final key in [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowDown,
  ]) {
    testWidgets(
      '${key.keyLabel} does not carry focus out of the panel, so Back still closes it',
      (tester) async {
        var pageBack = 0;
        await tester.pumpWidget(
          _app(
            resources: const [
              PlexResource(
                name: 'Home',
                owned: true,
                machineIdentifier: 'home-id',
              ),
            ],
            onPageBack: () => pageBack++,
          ),
        );
        await _openPanel(tester);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          pageBack,
          0,
          reason: 'Back belongs to the panel while it is open',
        );
        expect(find.byType(ServerSwitcherPanel), findsNothing);
      },
    );
  }
}
