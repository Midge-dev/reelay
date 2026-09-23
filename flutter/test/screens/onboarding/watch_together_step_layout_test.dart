import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/focusable_surface.dart';
import 'package:reelay/screens/onboarding/watch_together_step.dart';
import 'package:reelay/theme/scale.dart';

Future<void> _pump(WidgetTester tester, Size size, double factor) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: AppScale(
            factor: factor,
            child: WatchTogetherStep(onDone: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // O4: the "Skipping is fine" bar sits the handoff's 110 from the bottom,
  // not on the screen's edge.
  testWidgets('the skip bar keeps the design\'s bottom margin', (tester) async {
    await _pump(tester, const Size(1920, 1080), 1.0);
    expect(tester.takeException(), isNull);
    // Test fonts run wider than Inter, so the column may scroll; measure at
    // its end, where the margin under the bar is what's left on screen.
    final content = tester.stateList<ScrollableState>(find.byType(Scrollable)).last;
    content.position.jumpTo(content.position.maxScrollExtent);
    await tester.pump();
    final bar = find.ancestor(
      of: find.text('Skipping is fine'),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.foregroundPainter is LeadingSpinePainter,
      ),
    );
    expect(1080 - tester.getRect(bar).bottom, closeTo(110, 1));
  });

  for (final uiScale in [1.0, 1.3, 1.5]) {
    testWidgets('lays out without overflow at ${(uiScale * 100).round()}% on the Shield\'s canvas', (tester) async {
      await _pump(tester, const Size(960, 540), 540 / 1080 * uiScale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('focusing Not now brings the whole skip bar into view at 130%', (tester) async {
    await _pump(tester, const Size(960, 540), 540 / 1080 * 1.3);
    final notNow = find.ancestor(of: find.text('Not now'), matching: find.byType(Focus)).first;
    Focus.of(tester.element(find.text('Not now'))).requestFocus();
    await tester.pumpAndSettle();
    final bar = find.ancestor(
      of: find.text('Skipping is fine'),
      matching: find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is LeadingSpinePainter),
    );
    expect(tester.getRect(bar).bottom, lessThanOrEqualTo(540), reason: 'the bar is fully on screen');
    expect(notNow, findsOneWidget);
  });
}
