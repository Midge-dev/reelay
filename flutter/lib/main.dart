import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/settings/app_settings.dart';
import 'screens/app_root.dart';
import 'state/data_providers.dart';
import 'theme/scale.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: ReelayApp()));
}

class ReelayApp extends ConsumerWidget {
  const ReelayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Screen 22 — reapplied on every emission from settingsStreamProvider
    // (seeded at app start, then again whenever the Appearance screen saves
    // a new theme), so AppColors is always current before anything below
    // reads it. A build-time mutation of a plain static field, not
    // setState — the whole point is that nothing downstream needs its own
    // subscription to notice.
    AppColors.applyTheme(
      ref.watch(settingsStreamProvider).value?.themeId ?? ThemeId.nocturne,
    );
    // Screen 22's "UI Size" stepper — a manual multiplier on top of the
    // screenHeight/1080 factor, since no API tells a set-top box its
    // panel's real physical size (see AppSettings.uiScale's doc comment).
    final uiScale =
        ref.watch(settingsStreamProvider).value?.uiScale ??
        AppSettings.defaultUiScale;
    return WidgetsApp(
      title: 'Reelay',
      color: const Color(0xFF9184D9),
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
      // Establishes the one scale factor (screenHeight / 1080) the whole
      // app multiplies design units by — DESIGN.md non-negotiable #5. Do
      // this here, once, rather than at any individual screen, or the
      // numbers get hard-coded at 1.0.
      builder: (context, child) => AppScale(
        factor: (MediaQuery.sizeOf(context).height / 1080) * uiScale,
        child: child!,
      ),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        );
      },
    );
  }
}
