import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _trackWidth = 44.0;
const _trackHeight = 24.0;
const _thumbSize = 18.0;
const _thumbInset = 3.0;

const _switchBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
const _switchGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

/// Ports ui/kit/Switch.kt — the track color already carries on/off state,
/// so press feedback shrinks the thumb instead.
class AppSwitch extends StatefulWidget {
  final bool checked;
  final ValueChanged<bool> onCheckedChange;
  final FocusNode? focusNode;

  const AppSwitch({super.key, required this.checked, required this.onCheckedChange, this.focusNode});

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = SurfaceColors(
      container: widget.checked ? AppColors.accent : AppColors.surfaceVariant,
      content: AppColors.white,
    );
    final thumbOffset = widget.checked ? _trackWidth - _thumbSize - _thumbInset : _thumbInset;
    final thumbScale = _pressed ? 0.88 : 1.0;

    return SizedBox(
      width: _trackWidth,
      height: _trackHeight,
      child: FocusableSurface(
        onClick: () => widget.onCheckedChange(!widget.checked),
        focusNode: widget.focusNode,
        shape: const StadiumBorder(),
        colors: colors,
        border: _switchBorder,
        glow: _switchGlow,
        contentAlignment: AlignmentDirectional.centerStart,
        onPressChange: (pressed) => setState(() => _pressed = pressed),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              left: thumbOffset,
              top: _thumbInset,
              child: AnimatedScale(
                scale: thumbScale,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
