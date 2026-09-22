import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _rowMinHeight = 96.0;
const _badgeBorder = Border.fromBorderSide(
  BorderSide(color: AppColors.warning),
);

/// A real, visible placeholder for when Jellyfin support lands — disabled,
/// same treatment everywhere it appears (the server switcher's server
/// list, screen 06, and the add-profile dialog's account list, screen
/// 07b) rather than a functioning row or a code comment nobody sees.
class JellyfinComingSoonRow extends StatelessWidget {
  const JellyfinComingSoonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppShape.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const AppIcon(
                  PhosphorIconsRegular.hardDrives,
                  size: 26,
                  tint: AppColors.ink3,
                ),
                const SizedBox(width: AppSpacing.lg),
                const Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Jellyfin',
                        style: AppTypography.label,
                        color: AppColors.ink2,
                      ),
                      SizedBox(height: 3),
                      AppText(
                        'Not connectable yet',
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: _badgeBorder,
                    borderRadius: BorderRadius.circular(AppShape.radiusSm),
                  ),
                  child: const AppText(
                    'COMING SOON',
                    style: AppTypography.caption,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
