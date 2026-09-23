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
    final themeId =
        ref.watch(settingsStreamProvider).value?.themeId ?? ThemeId.nocturne;
    AppColors.applyTheme(themeId);
    // Screen 22's "UI Size" stepper — a manual multiplier on top of the
    // screenHeight/1080 factor, since no API tells a set-top box its
    // panel's real physical size (see AppSettings.uiScale's doc comment).
    final uiScale =
        ref.watch(settingsStreamProvider).value?.uiScale ??
        AppSettings.defaultUiScale;
    return WidgetsApp(
      title: 'Reelay',
      color: AppColors.accent,
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
      // Establishes the one scale factor (screenHeight / 1080) the whole
      // app multiplies design units by — DESIGN.md non-negotiable #5. Do
      // this here, once, rather than at any individual screen, or the
      // numbers get hard-coded at 1.0.
      builder: (context, child) => _ThemeRepaint(
        themeId: themeId,
        child: AppScale(
          factor: (MediaQuery.sizeOf(context).height / 1080) * uiScale,
          child: child!,
        ),
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

/// Screen 22 — "no cross-fade on change, swap and repaint". Widgets read
/// [AppColors] as plain static fields, so nothing subscribes to the theme;
/// and most of the tree is const (`home: const AppRoot()`), so rebuilding
/// [ReelayApp] alone never reaches it. When the theme changes, mark every
/// element below dirty once so each re-reads the new palette in the same
/// frame. State is untouched — this is a rebuild, not a remount.
class _ThemeRepaint extends StatefulWidget {
  final ThemeId themeId;
  final Widget child;

  const _ThemeRepaint({required this.themeId, required this.child});

  @override
  State<_ThemeRepaint> createState() => _ThemeRepaintState();
}

class _ThemeRepaintState extends State<_ThemeRepaint> {
  @override
  void didUpdateWidget(_ThemeRepaint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeId == widget.themeId) return;
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
