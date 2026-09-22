import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/settings/appearance_screen.dart';
import 'package:reelay/theme/tokens.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeId current = ThemeId.nocturne,
  ValueChanged<ThemeId>? onSelect,
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: AppearanceScreen(
        current: current,
        onSelect: onSelect ?? (_) {},
        onBack: onBack ?? () {},
        backFocus: FocusNode(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('lists every theme with its own one-line description', (
    tester,
  ) async {
    await _pump(tester);

    for (final id in ThemeId.values) {
      expect(find.text(id.label), findsOneWidget);
      expect(find.text(id.blurb), findsOneWidget);
    }
  });

  testWidgets(
    'tapping a theme row invokes onSelect with that theme, not the current one',
    (tester) async {
      ThemeId? selected;
      await _pump(
        tester,
        current: ThemeId.nocturne,
        onSelect: (id) => selected = id,
      );

      await tester.tap(find.text('Ember'));
      await tester.pump();

      expect(selected, ThemeId.ember);
    },
  );

  testWidgets('tapping the back pill invokes onBack', (tester) async {
    var backTapped = false;
    await _pump(tester, onBack: () => backTapped = true);

    await tester.tap(find.text('‹ Settings'));
    await tester.pump();

    expect(backTapped, isTrue);
  });

  testWidgets(
    'shows exactly one selected indicator, matching the current theme',
    (tester) async {
      await _pump(tester, current: ThemeId.sage);

      // One checkmark rendered for Sage and none of the other six rows.
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon?.fontFamily == 'PhosphorFill',
        ),
        findsOneWidget,
      );
    },
  );
}
