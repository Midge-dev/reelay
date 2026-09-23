import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _rowMinHeight = 96.0;
Border get _badgeBorder => Border.fromBorderSide(
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
        constraints: BoxConstraints(minHeight: _rowMinHeight.du(context)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl.du(context),
              vertical: AppSpacing.md.du(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIcon(
                  PhosphorIconsRegular.hardDrives,
                  size: 26,
                  tint: AppColors.ink3,
                ),
                SizedBox(width: AppSpacing.lg.du(context)),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Jellyfin',
                        style: AppTypography.label,
                        color: AppColors.ink2,
                      ),
                      SizedBox(height: 3.du(context)),
                      AppText(
                        'Not connectable yet',
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.lg.du(context)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm.du(context),
                    vertical: 2.du(context),
                  ),
                  decoration: BoxDecoration(
                    border: _badgeBorder,
                    borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
                  ),
                  child: AppText(
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
