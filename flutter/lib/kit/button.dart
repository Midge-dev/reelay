import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _buttonHeight = 62.0;
const _buttonContentPaddingHorizontal = AppSpacing.xxl;

const _buttonCompactHeight = 52.0;
const _buttonCompactContentPaddingHorizontal = AppSpacing.lg;

// The in-bar size (screen 01/11's Watch Together bar: 40 tall, radius 6,
// 18 padding-x) — the only place a button sits inside another surface's
// 68 du slot.
const _buttonDenseHeight = 40.0;
const _buttonDenseContentPaddingHorizontal = 18.0;

double _heightFor({required bool compact, required bool dense}) =>
    dense ? _buttonDenseHeight : (compact ? _buttonCompactHeight : _buttonHeight);

double _paddingFor({required bool compact, required bool dense}) => dense
    ? _buttonDenseContentPaddingHorizontal
    : (compact ? _buttonCompactContentPaddingHorizontal : _buttonContentPaddingHorizontal);

RoundedRectangleBorder _shapeFor(BuildContext context, {required bool dense}) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular((dense ? AppShape.radiusSm : AppShape.radiusMd).du(context)),
    );

SurfaceColors get _filledColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);
SurfaceBorder get _filledBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/Button.kt's `Button` — a filled button, radius 8 (not a
/// pill — the old stadium shape fought the 8px cards, see DESIGN.md).
class AppButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final bool compact;
  final bool dense;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.compact = false,
    this.dense = false,
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
      shape: _shapeFor(context, dense: dense),
      colors: _filledColors,
      border: _filledBorder,
      child: SizedBox(
        height: _heightFor(compact: compact, dense: dense).du(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _paddingFor(compact: compact, dense: dense).du(context),
          ),
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

SurfaceColors get _outlinedColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);
SurfaceBorder get _outlinedBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/Button.kt's `OutlinedButton` — the secondary action style.
class AppOutlinedButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final bool compact;
  final bool dense;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppOutlinedButton({
    super.key,
    required this.onClick,
    this.enabled = true,
    this.compact = false,
    this.dense = false,
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
      shape: _shapeFor(context, dense: dense),
      colors: _outlinedColors,
      border: _outlinedBorder,
      child: SizedBox(
        height: _heightFor(compact: compact, dense: dense).du(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _paddingFor(compact: compact, dense: dense).du(context),
          ),
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

SurfaceColors get _ghostColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.accent300,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
);
SurfaceBorder get _ghostBorder => SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// A borderless text action in accent300 — screen 11's "2 more rooms ›"
/// segment. No idle border or fill (it reads as a link inside the bar it
/// sits in); focus is the full signal like every other surface.
class AppGhostButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool dense;
  final FocusNode? focusNode;
  final Widget child;

  const AppGhostButton({super.key, required this.onClick, this.dense = false, this.focusNode, required this.child});

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onClick: onClick,
      focusNode: focusNode,
      shape: _shapeFor(context, dense: dense),
      colors: _ghostColors,
      border: _ghostBorder,
      child: SizedBox(
        height: _heightFor(compact: true, dense: dense).du(context),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.du(context)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      ),
    );
  }
}
