import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/common/no_servers_screen.dart';

const _resources = [
  PlexResource(name: 'Attic', owned: true),
  PlexResource(name: "Marcus's server", owned: false),
];

Future<void> _pump(
  WidgetTester tester, {
  List<PlexResource> resources = _resources,
  VoidCallback? onRetry,
  VoidCallback? onStartOver,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: NoServersScreen(
        resources: resources,
        onRetry: onRetry ?? () {},
        onStartOver: onStartOver ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('names every configured server as unreachable', (tester) async {
    await _pump(tester);

    expect(find.text("Can't reach any of your servers"), findsOneWidget);
    expect(find.text('Attic'), findsOneWidget);
    expect(find.text("Marcus's server"), findsOneWidget);
    expect(find.text('Unreachable'), findsNWidgets(2));
    expect(find.textContaining('2 servers are configured'), findsOneWidget);
  });

  testWidgets('tapping Try again now invokes onRetry', (tester) async {
    var retried = false;
    await _pump(tester, onRetry: () => retried = true);

    await tester.tap(find.text('Try again now'));
    await tester.pump();

    expect(retried, isTrue);
  });

  testWidgets('tapping Start over invokes onStartOver', (tester) async {
    var startedOver = false;
    await _pump(tester, onStartOver: () => startedOver = true);

    await tester.tap(find.text('Start over'));
    await tester.pump();

    expect(startedOver, isTrue);
  });

  testWidgets('counts down and retries automatically once it reaches zero', (tester) async {
    var retried = false;
    await _pump(tester, onRetry: () => retried = true);

    expect(find.text('Trying again on its own in 12 seconds'), findsOneWidget);

    await tester.pump(const Duration(seconds: 12));

    expect(retried, isTrue);
  });
}
