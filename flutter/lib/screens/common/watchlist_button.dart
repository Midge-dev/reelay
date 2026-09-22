import 'package:flutter/widgets.dart';

import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Ports ui/common/WatchlistButton.kt. Square, not round — this sits in the
/// detail-page action row alongside the other icon-only buttons (restart,
/// more), so it takes the same 62x62 frame-only treatment as AppIconButton
/// rather than a circular badge.
class WatchlistButton extends StatelessWidget {
  final bool isOnWatchlist;
  final VoidCallback onClick;
  final ValueChanged<bool>? onFocusChange;

  const WatchlistButton({
    super.key,
    required this.isOnWatchlist,
    required this.onClick,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final border = SurfaceBorder(
      idle: SurfaceBorderSide.solid(
        isOnWatchlist ? AppColors.accent : AppColors.lineStrong,
      ),
      focused: SurfaceBorderSide.solid(AppColors.accent),
      noSpine: true,
    );

    return AppIconButton(
      onClick: onClick,
      onFocusChange: onFocusChange,
      border: border,
      child: AppText(
        isOnWatchlist ? '✓' : '+',
        style: AppTypography.label,
        color: isOnWatchlist ? AppColors.accent : AppColors.ink2,
      ),
    );
  }
}
