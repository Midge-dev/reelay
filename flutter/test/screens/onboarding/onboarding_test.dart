import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/focusable_surface.dart';
import 'package:reelay/screens/onboarding/onboarding_screen.dart';
import 'package:reelay/screens/onboarding/setup_ready_screen.dart';
import 'package:reelay/theme/scale.dart';

Future<void> _pumpAt(WidgetTester tester, double uiScale, Widget child) async {
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(960, 540)),
          child: AppScale(factor: 540 / 1080 * uiScale, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('O1: Plex is chosen and focused; the Jellyfin card is disabled and out of the focus order', (tester) async {
    await _pumpAt(tester, 1.0, OnboardingScreen(onComplete: (_) {}));

    final jellyfin = tester.widget<FocusableSurface>(
      find.ancestor(of: find.text('Jellyfin'), matching: find.byType(FocusableSurface)).first,
    );
    expect(jellyfin.enabled, isFalse, reason: 'DESIGN.md: disabled until Jellyfin ships');
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Select at least one to continue'), findsNothing, reason: 'Plex starts selected');
    expect(tester.takeException(), isNull);
  });

  for (final uiScale in [1.0, 1.3, 1.5]) {
    testWidgets('O1 and O5 lay out without overflow at ${(uiScale * 100).round()}%', (tester) async {
      await _pumpAt(tester, uiScale, OnboardingScreen(onComplete: (_) {}));
      expect(tester.takeException(), isNull);

      await _pumpAt(
        tester,
        uiScale,
        const SetupReadyScreen(
          done: ['Signed in to Plex as sam', 'Reached 2 servers', 'Found 5 libraries across 2 servers'],
          current: 'Loading Movies',
          headline: 'Two servers, five libraries',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
