import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_auth_api.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/kit/filter_chip.dart';
import 'package:reelay/screens/navigation/server_switcher_panel.dart';
import 'package:reelay/state/app_state.dart';

const _atticServer = PlexServer(name: 'Attic', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', machineIdentifier: 'm1');
const _sectionGroups = [
  SectionGroup(type: 'movie', title: 'Movies', sectionsByServerId: {'m1': PlexSection(key: 's1', title: 'Movies', type: 'movie')}),
  SectionGroup(type: 'show', title: 'TV Shows', sectionsByServerId: {'m1': PlexSection(key: 's2', title: 'TV Shows', type: 'show')}),
];

const _resources = [
  PlexResource(name: 'Attic', owned: true, machineIdentifier: 'm1'),
  PlexResource(name: 'Loft', owned: false, machineIdentifier: 'm2'),
];

Future<void> _pump(
  WidgetTester tester, {
  List<ReachableServer>? connectedServers,
  Set<String>? disabledServerIds,
  List<PlexResource>? resources,
  Future<ReachableServer?> Function(PlexResource)? probeServer,
  ValueChanged<SectionGroup>? onSelectSection,
  void Function(PlexResource, bool)? onToggleServer,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          ServerSwitcherPanel(
            account: const PlexAccount(username: 'GrimLad'),
            connectedServers: connectedServers ?? const [ReachableServer(_atticServer, ServerReachability.local)],
            disabledServerIds: disabledServerIds ?? const {},
            sectionGroups: _sectionGroups,
            selectedSectionGroupKey: 'movie::movies',
            loadServers: () async => resources ?? _resources,
            probeServer: probeServer ?? (_) async => null,
            loadLibraryCount: (_) async => 2,
            onSelectSection: onSelectSection ?? (_) {},
            onToggleServer: onToggleServer ?? (_, _) {},
            onClose: onClose ?? () {},
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the title with the account username and every server row', (tester) async {
    await _pump(tester);

    expect(find.text("GrimLad's servers"), findsOneWidget);
    expect(find.text('Attic'), findsOneWidget);
    expect(find.text('Loft'), findsOneWidget);
  });

  testWidgets('an already-connected server shows Local and its real library count without probing', (tester) async {
    await _pump(tester);

    expect(find.text('Local'), findsOneWidget);
    expect(find.textContaining('2 libraries'), findsOneWidget);
  });

  testWidgets('a reachable non-connected server shows the probed reachability', (tester) async {
    await _pump(
      tester,
      probeServer: (resource) async => ReachableServer(
        const PlexServer(name: 'Loft', baseUrl: 'http://10.0.0.5:32400', accessToken: 'tok2'),
        ServerReachability.relayed,
      ),
    );
    await tester.pump();

    expect(find.text('Relayed'), findsOneWidget);
  });

  testWidgets('an unreachable server shows Unreachable and cannot be toggled', (tester) async {
    (PlexResource, bool)? toggled;
    await _pump(
      tester,
      probeServer: (_) async => null,
      onToggleServer: (r, enabled) => toggled = (r, enabled),
    );
    await tester.pump();

    expect(find.text('Unreachable'), findsOneWidget);

    await tester.tap(find.text('Loft'));
    await tester.pump();
    expect(toggled, isNull);
  });

  testWidgets('always shows a disabled Jellyfin row', (tester) async {
    await _pump(tester);

    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets('tapping a reachable, enabled server turns it off', (tester) async {
    (PlexResource, bool)? toggled;
    await _pump(
      tester,
      probeServer: (resource) async => ReachableServer(
        const PlexServer(name: 'Loft', baseUrl: 'http://10.0.0.5:32400', accessToken: 'tok2'),
        ServerReachability.local,
      ),
      onToggleServer: (r, enabled) => toggled = (r, enabled),
    );
    await tester.pump();

    await tester.tap(find.byType(AppCard).at(1));
    await tester.pump();

    expect(toggled?.$1.machineIdentifier, 'm2');
    expect(toggled?.$2, isFalse);
  });

  testWidgets('tapping a reachable, disabled server turns it on', (tester) async {
    (PlexResource, bool)? toggled;
    await _pump(
      tester,
      disabledServerIds: const {'m2'},
      probeServer: (resource) async => ReachableServer(
        const PlexServer(name: 'Loft', baseUrl: 'http://10.0.0.5:32400', accessToken: 'tok2'),
        ServerReachability.local,
      ),
      onToggleServer: (r, enabled) => toggled = (r, enabled),
    );
    await tester.pump();

    await tester.tap(find.byType(AppCard).at(1));
    await tester.pump();

    expect(toggled?.$1.machineIdentifier, 'm2');
    expect(toggled?.$2, isTrue);
  });

  testWidgets('tapping a library chip invokes onSelectSection and onClose', (tester) async {
    SectionGroup? selected;
    var closed = false;
    await _pump(tester, onSelectSection: (s) => selected = s, onClose: () => closed = true);

    await tester.tap(find.byType(AppFilterChip).last);
    await tester.pump();

    expect(selected?.key, 'show::tv shows');
    expect(closed, isTrue);
  });
}
