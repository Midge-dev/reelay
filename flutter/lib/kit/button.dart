import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _buttonMinWidth = 58.0;
const _buttonMinHeight = 40.0;
const _buttonContentPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);

const _buttonCompactMinHeight = 32.0;
const _buttonCompactContentPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);

final _filledColors = SurfaceColors(
  container: AppColors.surfaceVariant,
  content: AppColors.white,
  focusedContainer: AppColors.accent,
  pressedContainer: AppColors.accentPressed,
  disabledContent: AppColors.white.withValues(alpha: 0.5),
);
const _filledBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
const _filledGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

/// Ports ui/kit/Button.kt's `Button` — a pill-shaped filled button.
class AppButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final bool compact;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.compact = false,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onClick: onClick,
      enabled: enabled,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      shape: const StadiumBorder(),
      colors: _filledColors,
      border: _filledBorder,
      glow: _filledGlow,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compact ? 0 : _buttonMinWidth,
          minHeight: compact ? _buttonCompactMinHeight : _buttonMinHeight,
        ),
        child: Padding(
          padding: compact ? _buttonCompactContentPadding : _buttonContentPadding,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [child]),
        ),
      ),
    );
  }
}

final _outlinedColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.white,
  focusedContainer: AppColors.transparent,
  pressedContainer: AppColors.accent.withValues(alpha: 0.25),
  disabledContent: AppColors.white.withValues(alpha: 0.5),
);
const _outlinedBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.dimBorder),
  focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient),
);
const _outlinedGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

/// Ports ui/kit/Button.kt's `OutlinedButton`.
class AppOutlinedButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final bool compact;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppOutlinedButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.compact = false,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onClick: onClick,
      enabled: enabled,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      shape: const StadiumBorder(),
      colors: _outlinedColors,
      border: _outlinedBorder,
      glow: _outlinedGlow,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: compact ? 0 : _buttonMinWidth,
          minHeight: compact ? _buttonCompactMinHeight : _buttonMinHeight,
        ),
        child: Padding(
          padding: compact ? _buttonCompactContentPadding : _buttonContentPadding,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [child]),
        ),
      ),
    );
  }
}
