import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Screen 25 — "COULDN'T START". Names the failed server plainly (no raw
/// exception, no error codes — DESIGN.md's copy rule). Now that duplicate
/// folding exists, a reachable alternate copy (when [alternateServerName]/
/// [onPlayAlternate] are given) becomes the primary action — "Play from
/// Loft" in the mockup — with plain Retry demoted to a secondary option;
/// with no alternate, Retry stays primary exactly as before. Rendered as
/// its own full screen rather than a literal dialog over the dimmed detail
/// page — see PlaybackFailed's own doc comment for why.
class PlaybackFailedScreen extends StatefulWidget {
  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final String? alternateServerName;
  final VoidCallback? onPlayAlternate;

  const PlaybackFailedScreen({
    super.key,
    required this.reason,
    required this.onRetry,
    required this.onBack,
    this.alternateServerName,
    this.onPlayAlternate,
  });

  @override
  State<PlaybackFailedScreen> createState() => _PlaybackFailedScreenState();
}

class _PlaybackFailedScreenState extends State<PlaybackFailedScreen> {
  final _primaryFocus = FocusNode(debugLabel: 'playback-failed-primary');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _primaryFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
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
              Builder(
                builder: (context) {
                  final alternateName = widget.alternateServerName;
                  final onPlayAlternate = widget.onPlayAlternate;
                  final hasAlternate = alternateName != null && onPlayAlternate != null;
                  return Wrap(
                    // Wrap, not Row — three buttons (alternate offer, retry,
                    // back) can exceed this dialog's width at some scale
                    // factors, same overflow hazard as MovieDetailScreen's
                    // hero action row.
                    spacing: AppSpacing.md.du(context),
                    runSpacing: AppSpacing.md.du(context),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasAlternate)
                        AppButton(
                          onClick: onPlayAlternate,
                          focusNode: _primaryFocus,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon(PhosphorIconsFill.play, size: 22),
                              SizedBox(width: AppSpacing.sm.du(context)),
                              AppText('Play from $alternateName'),
                            ],
                          ),
                        ),
                      hasAlternate
                          ? AppOutlinedButton(
                              onClick: widget.onRetry,
                              child: const AppText('Try again'),
                            )
                          : AppButton(
                              onClick: widget.onRetry,
                              focusNode: _primaryFocus,
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
                      AppOutlinedButton(
                        onClick: widget.onBack,
                        child: const AppText('Back'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
