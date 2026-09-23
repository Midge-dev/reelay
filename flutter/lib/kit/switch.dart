import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'content_color.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _trackWidth = 72.0;
const _trackHeight = 40.0;
const _thumbSize = 28.0;
const _thumbInset = 4.0;

/// Too small for a leading spine, so focus is the border alone stepping to
/// accent — the track's own fill already carries on/off state.
SurfaceBorder get _switchBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// Ports ui/kit/Switch.kt — the track color already carries on/off state,
/// so press feedback shrinks the thumb instead.
class AppSwitch extends StatefulWidget {
  final bool checked;
  final ValueChanged<bool> onCheckedChange;
  final FocusNode? focusNode;

  const AppSwitch({
    super.key,
    required this.checked,
    required this.onCheckedChange,
    this.focusNode,
  });

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = SurfaceColors(
      container: widget.checked ? AppColors.accent700 : AppColors.surface,
      content: AppColors.ink3,
      focusedContainer: widget.checked
          ? AppColors.accent700
          : AppColors.surfaceRaised,
      focusedContent: AppColors.ink,
    );
    final trackWidth = _trackWidth.du(context);
    final thumbSize = _thumbSize.du(context);
    final thumbInset = _thumbInset.du(context);
    final thumbOffset = widget.checked
        ? trackWidth - thumbSize - thumbInset
        : thumbInset;
    final thumbScale = _pressed ? 0.88 : 1.0;

    return SizedBox(
      width: trackWidth,
      height: _trackHeight.du(context),
      child: FocusableSurface(
        onClick: () => widget.onCheckedChange(!widget.checked),
        focusNode: widget.focusNode,
        shape: const StadiumBorder(),
        colors: colors,
        border: _switchBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        onPressChange: (pressed) => setState(() => _pressed = pressed),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              left: thumbOffset,
              top: thumbInset,
              child: AnimatedScale(
                scale: thumbScale,
                duration: const Duration(milliseconds: 100),
                child: Builder(
                  builder: (context) => Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ContentColor.of(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
