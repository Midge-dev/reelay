import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _watchlistButtonSize = 44.0;

/// Ports ui/common/WatchlistButton.kt.
class WatchlistButton extends StatelessWidget {
  final bool isOnWatchlist;
  final VoidCallback onClick;
  final ValueChanged<bool>? onFocusChange;

  const WatchlistButton({super.key, required this.isOnWatchlist, required this.onClick, this.onFocusChange});

  @override
  Widget build(BuildContext context) {
    final colors = isOnWatchlist
        ? SurfaceColors(
            container: AppColors.accent.withValues(alpha: 0.3),
            content: AppColors.white,
            focusedContainer: AppColors.accent,
            pressedContainer: AppColors.accentPressed,
          )
        : SurfaceColors(
            container: AppColors.transparent,
            content: AppColors.white,
            focusedContainer: AppColors.accent,
            pressedContainer: AppColors.accentPressed,
          );
    final border = SurfaceBorder(
      idle: isOnWatchlist
          ? const SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient)
          : const SurfaceBorderSide.solid(AppColors.dimBorder),
      focused: const SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient),
    );

    return SizedBox(
      width: _watchlistButtonSize,
      height: _watchlistButtonSize,
      child: FocusableSurface(
        onClick: onClick,
        onFocusChange: onFocusChange,
        shape: const CircleBorder(),
        colors: colors,
        border: border,
        glow: const SurfaceGlow(focusedColor: AppColors.accentGlow),
        child: AppText(isOnWatchlist ? '✓' : '+', style: AppTypography.titleLarge),
      ),
    );
  }
}
