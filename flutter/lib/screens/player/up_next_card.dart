import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

const _countdownSeconds = 12;

/// Screen 16 — bottom-right, over the credits rather than replacing them,
/// with a countdown bar underneath. It appears only in the last seconds, so
/// Play takes focus: one press plays the next episode. Pressing Back
/// dismisses it for the rest of the episode (PlayerScreen's
/// _upNextDismissed, not just clearing this widget).
class UpNextCard extends StatefulWidget {
  final PlexServer server;
  final PlexOnDeckItem item;
  final VoidCallback onPlayNow;
  final VoidCallback onDismiss;

  const UpNextCard({
    super.key,
    required this.server,
    required this.item,
    required this.onPlayNow,
    required this.onDismiss,
  });

  @override
  State<UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<UpNextCard> {
  int _secondsLeft = _countdownSeconds;
  Timer? _timer;
  final _playFocus = FocusNode(debugLabel: 'up-next-play');

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _tick(Timer timer) {
    if (!mounted) return;
    if (_secondsLeft <= 1) {
      timer.cancel();
      widget.onPlayNow();
      return;
    }
    setState(() => _secondsLeft -= 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final episodeLabel = item.index != null
        ? 'UP NEXT · EPISODE ${item.index}'
        : 'UP NEXT';
    final card = Container(
      width: 760.du(context),
      padding: EdgeInsets.all(AppSpacing.xxl.du(context)),
      decoration: BoxDecoration(
        color: AppScrims.chip,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
        boxShadow: AppElevation.overlay,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 260.du(context),
                height: 146.du(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusMd.du(context),
                  ),
                  child: Artwork(
                    imageUrl: PlexImageUrl.of(widget.server, item.thumb),
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.xl.du(context)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      episodeLabel,
                      style: AppTypography.micro,
                      color: AppColors.accent300,
                    ),
                    SizedBox(height: AppSpacing.sm.du(context)),
                    AppText(
                      item.title,
                      style: AppTypography.title2,
                      color: AppColors.inkOnArt,
                      maxLines: 1,
                    ),
                    if (item.summary case final summary?
                        when summary.isNotEmpty) ...[
                      SizedBox(height: AppSpacing.sm.du(context)),
                      AppText(
                        summary,
                        style: AppTypography.caption.copyWith(height: 1.5),
                        color: AppColors.ink2,
                        maxLines: 2,
                      ),
                    ],
                    SizedBox(height: 20.du(context)),
                    Wrap(
                      spacing: AppSpacing.md.du(context),
                      runSpacing: AppSpacing.sm.du(context),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppButton(
                          onClick: widget.onPlayNow,
                          focusNode: _playFocus,
                          autofocus: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon(PhosphorIconsFill.play, size: 20),
                              SizedBox(width: AppSpacing.sm.du(context)),
                              AppText('Play in $_secondsLeft'),
                            ],
                          ),
                        ),
                        AppOutlinedButton(
                          onClick: widget.onDismiss,
                          child: const AppText('Not now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    // The countdown, drawn under the card as screen 16 does: it fills as
    // the seconds run out, so the auto-play is never a surprise.
    final elapsed = (_countdownSeconds - _secondsLeft + 1) / _countdownSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        SizedBox(height: 16.du(context)),
        SizedBox(
          width: 760.du(context),
          height: 4.du(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2.du(context)),
            child: ColoredBox(
              color: AppColors.inkOnArt.withValues(alpha: 0.22),
              child: AnimatedFractionallySizedBox(
                duration: const Duration(seconds: 1),
                alignment: Alignment.centerLeft,
                widthFactor: elapsed.clamp(0.0, 1.0),
                child: ColoredBox(color: AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
