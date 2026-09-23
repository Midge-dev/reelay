import 'package:flutter/widgets.dart';

/// The single scale factor the whole app multiplies design units (du) by —
/// see DESIGN.md non-negotiable #5. `scale = screenHeight / 1080`,
/// established once near the root (in main.dart) and never per-widget,
/// never a breakpoint. Sizes (type, card heights, safe area, radii) follow
/// screen height; counts (grid columns, cards per row) follow remaining
/// width and don't go through this at all.
///
/// Most Android TV boxes report a 1920x1080 logical surface regardless of
/// panel resolution, so `factor` is 1.0 in the overwhelming majority of
/// real deployments today; a 720p stick reports 1280x720 -> ~0.667.
class AppScale extends InheritedWidget {
  final double factor;

  const AppScale({super.key, required this.factor, required super.child});

  // No assert on a missing ancestor — matches ContentColor.of's fallback
  // convention. main.dart always wraps the real app in one; widget tests
  // that render a kit component in isolation (no app root) get an
  // unscaled 1:1 factor instead of a hard crash.
  static double of(BuildContext context) {
    final scale = context.dependOnInheritedWidgetOfExactType<AppScale>();
    return scale?.factor ?? 1.0;
  }

  @override
  bool updateShouldNotify(AppScale oldWidget) => factor != oldWidget.factor;
}

/// `value.du(context)` — converts a 1080p design-unit value to logical
/// pixels for the current screen. `du` is unitless in the token spec; 1 du
/// == 1 logical pixel at the 1920x1080 reference.
extension DesignUnits on num {
  double du(BuildContext context) => toDouble() * AppScale.of(context);
}
