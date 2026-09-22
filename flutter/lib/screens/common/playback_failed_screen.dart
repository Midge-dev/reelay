import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Screen 25 — "COULDN'T START". Names the failed server plainly (no raw
/// exception, no error codes — DESIGN.md's copy rule), offers Retry as the
/// primary action. No alternate-source offer yet (see PlaybackFailed's doc
/// comment: needs cross-server duplicate folding, which doesn't exist).
/// Rendered as its own full screen rather than a literal dialog over the
/// dimmed detail page — see the same state's doc comment for why.
class PlaybackFailedScreen extends StatefulWidget {
  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const PlaybackFailedScreen({
    super.key,
    required this.reason,
    required this.onRetry,
    required this.onBack,
  });

  @override
  State<PlaybackFailedScreen> createState() => _PlaybackFailedScreenState();
}

class _PlaybackFailedScreenState extends State<PlaybackFailedScreen> {
  final _retryFocus = FocusNode(debugLabel: 'playback-failed-retry');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _retryFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Container(
          width: 900.du(context),
          padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
          decoration: BoxDecoration(
            color: AppColors.surfaceOverlay,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
            boxShadow: AppElevation.overlay,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(
                    PhosphorIconsRegular.warning,
                    size: 28,
                    tint: AppColors.warning,
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppText(
                    "COULDN'T START",
                    style: AppTypography.micro,
                    color: AppColors.warning,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xl.du(context)),
              AppText(widget.reason, style: AppTypography.title2),
              SizedBox(height: AppSpacing.xxl.du(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    onClick: widget.onRetry,
                    focusNode: _retryFocus,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          PhosphorIconsRegular.arrowClockwise,
                          size: 22,
                        ),
                        SizedBox(width: AppSpacing.sm.du(context)),
                        const AppText('Try again'),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppOutlinedButton(
                    onClick: widget.onBack,
                    child: const AppText('Back'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
