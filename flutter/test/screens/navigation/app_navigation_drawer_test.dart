import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/navigation/app_navigation_drawer.dart';
import 'package:reelay/state/app_state.dart';
import 'package:reelay/theme/phosphor_icons.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'home-id');
const _connectedServers = [ReachableServer(_server, ServerReachability.local)];

const _sections = [
  SectionGroup(type: 'movie', title: 'Movies', sectionsByServerId: {'home-id': PlexSection(key: 's1', title: 'Movies', type: 'movie')}),
  SectionGroup(type: 'show', title: 'Shows', sectionsByServerId: {'home-id': PlexSection(key: 's2', title: 'Shows', type: 'show')}),
];

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(size: Size(1920, 1080)), child: child),
    ),
  );
}

void main() {
  testWidgets('renders every section plus Home/Settings as icons, labels hidden while collapsed', (tester) async {
    await _pump(
      tester,
      AppNavigationDrawer(
        sectionGroups: _sections,
        destination: RailDestination.home,
        onSelectSection: (_) {},
        onOpenSettings: () {},
        onOpenHome: () {},
        onOpenSearch: () {},
        loadServers: () async => const [],
        probeServer: (_) async => null,
        loadLibraryCount: (_) async => null,
        connectedServers: _connectedServers,
        disabledServerIds: const {},
        onToggleServer: (_, _) {},
        child: const SizedBox(),
      ),
    );

    expect(find.byIcon(PhosphorIconsFill.house), findsOneWidget, reason: 'Home is the selected item, so it shows the Fill weight');
    expect(find.byIcon(PhosphorIconsRegular.gear), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.filmSlate), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.televisionSimple), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.bookmarkSimple), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.usersThree), findsOneWidget);
    expect(find.text('Home'), findsNothing, reason: 'labels are hidden until the rail is focused/expanded');
    expect(tester.takeException(), isNull);
  });

  testWidgets('focusing an item expands the rail and reveals labels', (tester) async {
    await _pump(
      tester,
      AppNavigationDrawer(
        sectionGroups: _sections,
        destination: RailDestination.home,
        onSelectSection: (_) {},
        onOpenSettings: () {},
        onOpenHome: () {},
        onOpenSearch: () {},
        loadServers: () async => const [],
        probeServer: (_) async => null,
        loadLibraryCount: (_) async => null,
        connectedServers: _connectedServers,
        disabledServerIds: const {},
        onToggleServer: (_, _) {},
        child: const SizedBox(),
      ),
    );

    await tester.tap(find.byIcon(PhosphorIconsRegular.gear));
    await tester.pump();
    await tester.pump();
    await tester.pump(_railAnimDurationForTest);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
  });

  testWidgets('tapping a section icon invokes onSelectSection with that section', (tester) async {
    SectionGroup? selected;
    await _pump(
      tester,
      AppNavigationDrawer(
        sectionGroups: _sections,
        destination: RailDestination.home,
        onSelectSection: (s) => selected = s,
        onOpenSettings: () {},
        onOpenHome: () {},
        onOpenSearch: () {},
        loadServers: () async => const [],
        probeServer: (_) async => null,
        loadLibraryCount: (_) async => null,
        connectedServers: _connectedServers,
        disabledServerIds: const {},
        onToggleServer: (_, _) {},
        child: const SizedBox(),
      ),
    );

    await tester.tap(find.byIcon(PhosphorIconsRegular.televisionSimple));
    await tester.pump();

    expect(selected?.key, 'show::shows');
  });

  testWidgets('tapping Settings invokes onOpenSettings', (tester) async {
    var opened = false;
    await _pump(
      tester,
      AppNavigationDrawer(
        sectionGroups: _sections,
        destination: RailDestination.home,
        onSelectSection: (_) {},
        onOpenSettings: () => opened = true,
        onOpenHome: () {},
        onOpenSearch: () {},
        loadServers: () async => const [],
        probeServer: (_) async => null,
        loadLibraryCount: (_) async => null,
        connectedServers: _connectedServers,
        disabledServerIds: const {},
        onToggleServer: (_, _) {},
        child: const SizedBox(),
      ),
    );

    await tester.tap(find.byIcon(PhosphorIconsRegular.gear));
    await tester.pump();

    expect(opened, isTrue);
  });
}

const _railAnimDurationForTest = Duration(milliseconds: 250);
