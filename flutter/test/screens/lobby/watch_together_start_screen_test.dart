import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/lobby/watch_together_start_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool defaultRestart = false,
  int maxSeats = 8,
  String? relayNickname = 'Relay server',
  Future<bool> Function()? checkRelayReachable,
  void Function({required bool restart, required bool showPhoneChat})? onConfirm,
  VoidCallback? onCancel,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: WatchTogetherStartScreen(
        roomTitle: 'The Quiet Coast',
        defaultRestart: defaultRestart,
        maxSeats: maxSeats,
        relayNickname: relayNickname,
        checkRelayReachable: checkRelayReachable,
        onConfirm: onConfirm ?? ({required restart, required showPhoneChat}) {},
        onCancel: onCancel ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows the room title, seat count, and Resume preselected by default', (tester) async {
    await _pump(tester);

    expect(find.text('Start a room for The Quiet Coast'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Start from the beginning'), findsOneWidget);
  });

  testWidgets('confirming without changing anything reports restart:false', (tester) async {
    bool? restarted;
    await _pump(tester, onConfirm: ({required restart, required showPhoneChat}) => restarted = restart);

    await tester.tap(find.text('Open the room'));
    await tester.pump();

    expect(restarted, isFalse);
  });

  testWidgets('defaultRestart:true preselects restart, and confirming reports it', (tester) async {
    bool? restarted;
    await _pump(tester, defaultRestart: true, onConfirm: ({required restart, required showPhoneChat}) => restarted = restart);

    await tester.tap(find.text('Open the room'));
    await tester.pump();

    expect(restarted, isTrue);
  });

  testWidgets('selecting "Start from the beginning" flips the choice before confirming', (tester) async {
    bool? restarted;
    await _pump(tester, onConfirm: ({required restart, required showPhoneChat}) => restarted = restart);

    await tester.tap(find.text('Start from the beginning'));
    await tester.pump();
    await tester.tap(find.text('Open the room'));
    await tester.pump();

    expect(restarted, isTrue);
  });

  testWidgets('tapping Cancel invokes onCancel', (tester) async {
    var cancelled = false;
    await _pump(tester, onCancel: () => cancelled = true);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('runs the real reachability check and shows the result', (tester) async {
    await _pump(tester, checkRelayReachable: () async => true);
    await tester.pump();

    expect(find.textContaining('Relay reachable'), findsOneWidget);
  });

  testWidgets('shows an unreachable relay honestly, not a generic message', (tester) async {
    await _pump(tester, checkRelayReachable: () async => false);
    await tester.pump();

    expect(find.textContaining("didn't answer"), findsOneWidget);
  });
}
