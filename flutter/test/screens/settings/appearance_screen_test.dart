import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/settings/appearance_screen.dart';
import 'package:reelay/theme/phosphor_icons.dart';
import 'package:reelay/theme/tokens.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeId current = ThemeId.nocturne,
  ValueChanged<ThemeId>? onSelect,
  double uiScale = AppSettings.defaultUiScale,
  ValueChanged<double>? onSelectUiScale,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        child: Column(
          children: [
            UiScaleStepper(value: uiScale, onChanged: onSelectUiScale ?? (_) {}),
            ThemeList(current: current, onSelect: onSelect ?? (_) {}),
          ],
        ),
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

  group('UI Size stepper', () {
    testWidgets('shows the current scale as a percentage', (tester) async {
      await _pump(tester, uiScale: 1.25);

      expect(find.text('125%'), findsOneWidget);
    });

    testWidgets('tapping + steps up by one increment', (tester) async {
      double? selected;
      await _pump(tester, uiScale: 1.2, onSelectUiScale: (v) => selected = v);

      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pump();

      expect(selected, closeTo(1.2 + AppSettings.uiScaleStep, 0.001));
    });

    testWidgets('tapping - steps down by one increment', (tester) async {
      double? selected;
      await _pump(tester, uiScale: 1.2, onSelectUiScale: (v) => selected = v);

      await tester.tap(find.byIcon(PhosphorIconsRegular.minus));
      await tester.pump();

      expect(selected, closeTo(1.2 - AppSettings.uiScaleStep, 0.001));
    });

    testWidgets('- is disabled at the minimum', (tester) async {
      double? selected;
      await _pump(
        tester,
        uiScale: AppSettings.minUiScale,
        onSelectUiScale: (v) => selected = v,
      );

      await tester.tap(find.byIcon(PhosphorIconsRegular.minus));
      await tester.pump();

      expect(selected, isNull);
    });

    testWidgets('+ is disabled at the maximum', (tester) async {
      double? selected;
      await _pump(
        tester,
        uiScale: AppSettings.maxUiScale,
        onSelectUiScale: (v) => selected = v,
      );

      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pump();

      expect(selected, isNull);
    });

    testWidgets('no reset shortcut shown at the default scale', (tester) async {
      await _pump(tester, uiScale: AppSettings.defaultUiScale);

      expect(find.textContaining('Reset to'), findsNothing);
    });

    testWidgets('tapping the reset shortcut returns to the default scale', (tester) async {
      double? selected;
      await _pump(tester, uiScale: AppSettings.maxUiScale, onSelectUiScale: (v) => selected = v);

      await tester.tap(find.text('Reset to ${(AppSettings.defaultUiScale * 100).round()}%'));
      await tester.pump();

      expect(selected, AppSettings.defaultUiScale);
    });
  });
}
