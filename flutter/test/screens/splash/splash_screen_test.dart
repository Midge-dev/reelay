import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/splash/splash_screen.dart';
import 'package:reelay/theme/scale.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> ready,
  required VoidCallback onDone,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(1920, 1080),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: AppScale(
          factor: 1,
          child: SplashScreen(ready: ready, onDone: onDone),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('never exits before 2.4 s, even when ready at once', (
    tester,
  ) async {
    var done = false;
    await _pump(tester, ready: Future.value(), onDone: () => done = true);

    await tester.pump(const Duration(milliseconds: 2300));
    expect(done, isFalse);
    // 2.4 s hold, then the 300 ms exit fade.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(done, isTrue);
  });

  testWidgets('holds for a slow load, then exits once ready', (tester) async {
    var done = false;
    final ready = Completer<void>();
    await _pump(tester, ready: ready.future, onDone: () => done = true);

    await tester.pump(const Duration(seconds: 4));
    expect(done, isFalse);

    ready.complete();
    // Finish the current breath on its peak (≤ 900 ms), then 300 ms exit.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done, isTrue);
  });

  testWidgets('draws the lockup: wordmark text, both bars', (tester) async {
    await _pump(tester, ready: Completer<void>().future, onDone: () {});
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('Reelay'), findsOneWidget);
    // Let pending timers finish so the test ends cleanly.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('reduced motion still exits on the same rule', (tester) async {
    var done = false;
    await _pump(
      tester,
      ready: Future.value(),
      onDone: () => done = true,
      reducedMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 2450));
    await tester.pump(const Duration(milliseconds: 350));
    expect(done, isTrue);
  });
}
