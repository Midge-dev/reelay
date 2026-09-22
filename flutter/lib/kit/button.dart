import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _buttonHeight = 62.0;
const _buttonContentPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xxl);

const _buttonCompactHeight = 52.0;
const _buttonCompactContentPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.lg,
);

final _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd),
);

final _filledColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);
final _filledBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/Button.kt's `Button` — a filled button, radius 8 (not a
/// pill — the old stadium shape fought the 8px cards, see DESIGN.md).
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
      shape: _buttonShape,
      colors: _filledColors,
      border: _filledBorder,
      child: SizedBox(
        height: compact ? _buttonCompactHeight : _buttonHeight,
        child: Padding(
          padding: compact
              ? _buttonCompactContentPadding
              : _buttonContentPadding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [child],
          ),
        ),
      ),
    );
  }
}

final _outlinedColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);
final _outlinedBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/Button.kt's `OutlinedButton` — the secondary action style.
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
      shape: _buttonShape,
      colors: _outlinedColors,
      border: _outlinedBorder,
      child: SizedBox(
        height: compact ? _buttonCompactHeight : _buttonHeight,
        child: Padding(
          padding: compact
              ? _buttonCompactContentPadding
              : _buttonContentPadding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [child],
          ),
        ),
      ),
    );
  }
}
