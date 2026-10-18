import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/kit/focusable_surface.dart';
import 'package:reelay/screens/onboarding/jellyfin_link_step.dart';
import 'package:reelay/screens/onboarding/onboarding_frame.dart';
import 'package:reelay/screens/onboarding/onboarding_screen.dart';
import 'package:reelay/screens/onboarding/setup_ready_screen.dart';
import 'package:reelay/theme/scale.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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

/// O3 needs a device id; preferences stay as they were for every other
/// test, so the Plex link step's own behaviour isn't changed under it.
void _useInMemoryPrefs() {
  final original = SharedPreferencesAsyncPlatform.instance;
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
}

void main() {
  testWidgets('O1: Plex starts chosen; Jellyfin is a live choice beside it', (
    tester,
  ) async {
    await _pumpAt(tester, 1.0, OnboardingScreen(onComplete: (_) {}));

    FocusableSurface card(String title) => tester.widget<FocusableSurface>(
      find
          .ancestor(
            of: find.text(title),
            matching: find.byType(FocusableSurface),
          )
          .first,
    );
    expect(card('Jellyfin').enabled, isTrue);
    expect(card('Jellyfin').selected, isFalse);
    expect(card('Plex').selected, isTrue);
    expect(find.text('COMING SOON'), findsNothing);

    await tester.tap(find.text('Jellyfin'));
    await tester.pump();
    expect(card('Jellyfin').selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'O1: Jellyfin alone goes straight to linking Jellyfin, with Back rather than Skip',
    (tester) async {
      _useInMemoryPrefs();
      await _pumpAt(tester, 1.0, OnboardingScreen(onComplete: (_) {}));
      await tester.tap(find.text('Plex'));
      await tester.tap(find.text('Jellyfin'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Fill this in from your phone'), findsOneWidget);
      expect(
        find.text('Skip Jellyfin'),
        findsNothing,
        reason: 'nothing to go on to without it',
      );
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final uiScale in [1.0, 1.3, 1.5]) {
    testWidgets(
      'O3 and O3b lay out without overflow at ${(uiScale * 100).round()}%',
      (tester) async {
        _useInMemoryPrefs();
        await _pumpAt(
          tester,
          uiScale,
          JellyfinLinkStep(
            kicker: 'STEP 2 OF 4 · JELLYFIN',
            summaries: const {
              SetupStep.servers: 'Plex, Jellyfin',
              SetupStep.link: '2 of 2',
            },
            onLinked: (_, _) {},
            onBack: () {},
            onSkip: () {},
          ),
        );
        expect(find.text('Skip Jellyfin'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Type it on the TV instead'));
        await tester.pump();
        await tester.tap(find.text('Type it on the TV instead'));
        await tester.pump();
        expect(find.text('Type it in with the remote'), findsOneWidget);
        expect(find.text('Test and continue'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final uiScale in [1.0, 1.3, 1.5]) {
    testWidgets(
      'O1 and O5 lay out without overflow at ${(uiScale * 100).round()}%',
      (tester) async {
        await _pumpAt(tester, uiScale, OnboardingScreen(onComplete: (_) {}));
        expect(tester.takeException(), isNull);

        await _pumpAt(
          tester,
          uiScale,
          const SetupReadyScreen(
            done: [
              'Signed in to Plex as sam',
              'Reached 2 servers',
              'Found 5 libraries across 2 servers',
            ],
            current: 'Loading Movies',
            headline: 'Two servers, five libraries',
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Plex revoked this TV's sign-in (removed from the account's devices):
  // setup opens on linking and says why, instead of a raw 401.
  for (final uiScale in [1.0, 1.3]) {
    testWidgets(
      'relinking opens on the link step and says why at ${(uiScale * 100).round()}%',
      (tester) async {
        await _pumpAt(
          tester,
          uiScale,
          OnboardingScreen(relinking: true, onComplete: (_) {}),
        );
        expect(find.text('PLEX SIGNED THIS TV OUT'), findsOneWidget);
        expect(find.text('Link this TV to Plex again'), findsOneWidget);
        expect(
          find.text('Where’s your library?'),
          findsNothing,
          reason: 'not the servers step',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Settings → Servers → Add more servers: the same O1 → O2/O3, for a
  // profile that already has accounts.
  const sam = Profile(
    id: 'p1',
    name: 'Sam',
    watchTogetherName: 'Sam',
    plexUsername: 'sam',
    jellyfin: JellyfinLink(
      serverId: 's1',
      serverName: 'Loft',
      baseUrl: 'http://loft:8096',
      userId: 'u1',
      username: 'samj',
    ),
  );

  for (final uiScale in [1.0, 1.5]) {
    testWidgets(
      'adding servers: O1 opens with nothing chosen, names the accounts it has, and Back cancels at ${(uiScale * 100).round()}%',
      (tester) async {
        var cancelled = false;
        await _pumpAt(
          tester,
          uiScale,
          OnboardingScreen(
            addingTo: sam,
            onCancel: () => cancelled = true,
            onComplete: (_) {},
          ),
        );
        expect(find.text('What would you like to add?'), findsOneWidget);
        expect(find.text('SETUP'), findsNothing, reason: 'no step column');
        expect(find.textContaining('Signed in as sam'), findsOneWidget);
        expect(
          find.textContaining('Signed in to Loft as samj'),
          findsOneWidget,
        );
        expect(find.text('Select at least one to continue'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Back'));
        await tester.tap(find.text('Back'));
        await tester.pump();
        expect(cancelled, isTrue);
      },
    );
  }

  testWidgets('adding servers: Jellyfin goes to O3 without the step column', (
    tester,
  ) async {
    _useInMemoryPrefs();
    await _pumpAt(
      tester,
      1.0,
      OnboardingScreen(addingTo: sam, onCancel: () {}, onComplete: (_) {}),
    );
    await tester.tap(find.text('Jellyfin'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('ADD SERVERS · JELLYFIN'), findsOneWidget);
    expect(find.text('Fill this in from your phone'), findsOneWidget);
    expect(find.text('SETUP'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
