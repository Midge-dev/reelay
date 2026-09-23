import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

RoundedRectangleBorder _iconButtonShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
const _iconButtonSize = 62.0;

SurfaceColors get _iconButtonColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);

/// A spine would eat a quarter of a 62x62 square, so icon-only buttons take
/// the hairline frame alone — DESIGN.md non-negotiable #3.
SurfaceBorder get _defaultIconButtonBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// Square (not circular; only avatars and seat
/// circles are round in Nocturne), transparent at rest so it reads on the
/// scrims it usually sits over (player controls, a detail page's backdrop).
class AppIconButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  // Nullable rather than defaulting to _defaultIconButtonBorder directly —
  // see AppCard.border's matching comment.
  final SurfaceBorder? border;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppIconButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.border,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _iconButtonSize.du(context),
      height: _iconButtonSize.du(context),
      child: FocusableSurface(
        onClick: onClick,
        enabled: enabled,
        focusNode: focusNode,
        autofocus: autofocus,
        onFocusChange: onFocusChange,
        shape: _iconButtonShape(context),
        colors: _iconButtonColors,
        border: border ?? _defaultIconButtonBorder,
        child: child,
      ),
    );
  }
}
