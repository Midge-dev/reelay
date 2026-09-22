import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

final _chipShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusSm),
);
const _chipHeight = 48.0;
const _chipContentPadding = EdgeInsets.symmetric(horizontal: 22);

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
      shape: _chipShape,
      colors: _chipColors,
      border: _chipBorder,
      child: SizedBox(
        height: _chipHeight,
        child: Padding(
          padding: _chipContentPadding,
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
