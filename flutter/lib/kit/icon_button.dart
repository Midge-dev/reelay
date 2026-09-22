import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

final _iconButtonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.radiusMd));
const _iconButtonSize = 62.0;

final _iconButtonColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);

/// A spine would eat a quarter of a 62x62 square, so icon-only buttons take
/// the hairline frame alone — DESIGN.md non-negotiable #3.
const _defaultIconButtonBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// Ports ui/kit/IconButton.kt — square (not circular; only avatars and seat
/// circles are round in Nocturne), transparent at rest so it reads on the
/// scrims it usually sits over (player controls, a detail page's backdrop).
class AppIconButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final SurfaceBorder border;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppIconButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.border = _defaultIconButtonBorder,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _iconButtonSize,
      height: _iconButtonSize,
      child: FocusableSurface(
        onClick: onClick,
        enabled: enabled,
        focusNode: focusNode,
        autofocus: autofocus,
        onFocusChange: onFocusChange,
        shape: _iconButtonShape,
        colors: _iconButtonColors,
        border: border,
        child: child,
      ),
    );
  }
}
