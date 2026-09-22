import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

const _countdownSeconds = 12;

/// Screen 16 — bottom-right, over the credits rather than replacing them;
/// counts down but never steals focus mid-scene (autofocus is intentionally
/// not set here — see PlayerScreen's own focus handling, which leaves
/// playback controls as the default target). Pressing Back dismisses it for
/// the rest of the episode (PlayerScreen's _upNextDismissed, not just
/// clearing this widget).
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
    final episodeLabel = item.index != null ? 'UP NEXT · EPISODE ${item.index}' : 'UP NEXT';
    return Container(
      width: 760,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppScrims.chip,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(AppShape.radiusLg),
        boxShadow: AppElevation.overlay,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 260,
                height: 146,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppShape.radiusMd),
                  child: Artwork(imageUrl: PlexImageUrl.of(widget.server, item.thumb)),
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(episodeLabel, style: AppTypography.micro, color: AppColors.accent300),
                    const SizedBox(height: AppSpacing.sm),
                    AppText(item.title, style: AppTypography.title2, color: AppColors.inkOnArt),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppButton(
                          onClick: widget.onPlayNow,
                          focusNode: _playFocus,
                          autofocus: true,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const AppIcon(PhosphorIconsFill.play, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            AppText('Play in $_secondsLeft'),
                          ]),
                        ),
                        AppOutlinedButton(onClick: widget.onDismiss, child: const AppText('Not now')),
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
  }
}
