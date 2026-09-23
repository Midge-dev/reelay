import 'package:flutter/widgets.dart';

import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/icon.dart';
import '../../theme/tokens.dart';
import '../../theme/phosphor_icons.dart';

/// The add-to-watchlist toggle. Square, not round — this sits in the
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
    // Screens 03/04: an outlined 62x62 square like its neighbours, the
    // glyph saying which state it's in — check when saved, plus when not.
    // No accent at rest; the accent is focus's alone.
    final border = SurfaceBorder(
      idle: SurfaceBorderSide.solid(AppColors.lineStrong),
      focused: SurfaceBorderSide.solid(AppColors.accent),
      noSpine: true,
    );

    return AppIconButton(
      onClick: onClick,
      onFocusChange: onFocusChange,
      border: border,
      child: AppIcon(
        isOnWatchlist ? PhosphorIconsRegular.check : PhosphorIconsRegular.plus,
        size: 24,
      ),
    );
  }
}
