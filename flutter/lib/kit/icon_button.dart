import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _iconButtonShape = CircleBorder();
const _iconButtonSize = 44.0;

final _iconButtonColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.white,
  focusedContainer: AppColors.accent,
  pressedContainer: AppColors.accentPressed,
  disabledContent: AppColors.white.withValues(alpha: 0.5),
);
const _defaultIconButtonBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
const _iconButtonGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

/// Ports ui/kit/IconButton.kt — transparent at rest so it floats over
/// video/photos (e.g. player controls).
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
        glow: _iconButtonGlow,
        child: child,
      ),
    );
  }
}
