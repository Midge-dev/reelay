import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/hold_feedback.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  // Screen 21: "The poster desaturates and draws in 4% over the hold, so the
  // gesture is visibly doing something before it fires. Releasing early
  // restores it."
  Future<ValueNotifier<bool>> pump(WidgetTester tester) async {
    final holding = ValueNotifier(false);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: HoldScope(holding: holding, child: const HoldFeedback(child: SizedBox(width: 100, height: 150))),
    ));
    return holding;
  }

  double scale(WidgetTester tester) => tester.widget<Transform>(find.byKey(HoldFeedback.transformKey)).transform.entry(0, 0);
  double saturation(WidgetTester tester) => HoldFeedback.saturationOf(tester.widget<ColorFiltered>(find.byKey(HoldFeedback.filterKey)));

  testWidgets('at rest: nothing in the way — no transform, no filter layer on every card in a grid', (tester) async {
    await pump(tester);
    expect(find.byKey(HoldFeedback.transformKey), findsNothing);
    expect(find.byKey(HoldFeedback.filterKey), findsNothing);
  });

  testWidgets('over the hold it draws in 4% and loses its colour', (tester) async {
    final holding = await pump(tester);
    holding.value = true;
    await tester.pump();
    await tester.pump(AppMotion.hold ~/ 2);
    expect(scale(tester), closeTo(0.98, 0.002), reason: 'halfway');
    expect(saturation(tester), closeTo(0.5, 0.02));
    await tester.pump(AppMotion.hold ~/ 2);
    expect(scale(tester), closeTo(0.96, 0.001));
    expect(saturation(tester), closeTo(0.0, 0.001));
  });

  testWidgets('let go early, it comes straight back', (tester) async {
    final holding = await pump(tester);
    holding.value = true;
    await tester.pump();
    await tester.pump(AppMotion.hold ~/ 2);
    holding.value = false;
    await tester.pump();
    await tester.pump(AppMotion.press);
    expect(find.byKey(HoldFeedback.filterKey), findsNothing, reason: 'back at rest');
  });

  testWidgets('outside a HoldScope it is just its child', (tester) async {
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: HoldFeedback(child: SizedBox())));
    expect(find.byKey(HoldFeedback.filterKey), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets("a hold keeps the artwork's own state (its fade-in doesn't replay)", (tester) async {
    final holding = ValueNotifier(false);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: HoldScope(holding: holding, child: const HoldFeedback(child: _Counter())),
    ));
    final before = tester.state<_CounterState>(find.byType(_Counter));
    holding.value = true;
    await tester.pump();
    await tester.pump(AppMotion.hold ~/ 2);
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(before));
    holding.value = false;
    await tester.pump();
    await tester.pump(AppMotion.press);
    expect(tester.state<_CounterState>(find.byType(_Counter)), same(before));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}
