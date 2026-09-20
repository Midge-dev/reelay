import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _chipShape = StadiumBorder();
const _chipContentPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);

final _chipColors = SurfaceColors(
  container: AppColors.surfaceVariant,
  content: AppColors.onSurfaceVariant,
  focusedContainer: AppColors.accent,
  focusedContent: AppColors.white,
  selectedContainer: AppColors.surfaceVariant,
  selectedContent: AppColors.white,
  disabledContent: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
);
const _chipBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
const _chipGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

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
      glow: _chipGlow,
      child: Padding(
        padding: _chipContentPadding,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [child]),
      ),
    );
  }
}
