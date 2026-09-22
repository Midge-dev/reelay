import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

RoundedRectangleBorder _chipShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
    );
const _chipHeight = 48.0;
const _chipContentPaddingHorizontal = 22.0;

final _chipColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink3,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surface,
  selectedContent: AppColors.ink,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.ink2,
);
final _chipBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/FilterChip.kt.
class AppFilterChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onClick;
  final bool enabled;
  final FocusNode? focusNode;
  final Widget child;

  const AppFilterChip({
    super.key,
    required this.selected,
    required this.onClick,
    this.enabled = true,
    this.focusNode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onClick: onClick,
      enabled: enabled,
      selected: selected,
      focusNode: focusNode,
      shape: _chipShape(context),
      colors: _chipColors,
      border: _chipBorder,
      child: SizedBox(
        height: _chipHeight.du(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _chipContentPaddingHorizontal.du(context),
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
