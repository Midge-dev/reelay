import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import 'home_posters.dart';

const _typeEpisode = 'episode';
const _heroHeight = 460.0;
const _heroBackdropWidthFraction = 0.62;
const _progressBarWidth = 380.0;

/// The resume hero — screen 01's opening element: the top in-progress item,
/// real data, no invented curation. Ports of the old "Continue Watching"
/// row's first card being autofocused, promoted to its own hero per the
/// Nocturne redesign.
///
/// No synopsis line: [PlexOnDeckItem] carries no summary field, and
/// DESIGN.md's "real data, no invented curation" means an absent field
/// stays absent rather than being papered over. No Episodes action either
/// — that needs the parent show's own ratingKey to fetch its season list,
/// which [PlexOnDeckItem] doesn't carry (only the detail screens, which
/// load the full record, can offer it) — and no restart action, since the
/// detail screen this hero's Resume action reaches already has one.
class HomeHero extends StatelessWidget {
  final PlexServer server;
  final PlexOnDeckItem item;
  final VoidCallback onResume;
  final ValueChanged<PlexOnDeckItem>? onWatchTogether;
  final FocusNode? resumeFocusNode;
  final bool autofocus;

  const HomeHero({
    super.key,
    required this.server,
    required this.item,
    required this.onResume,
    this.onWatchTogether,
    this.resumeFocusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEpisode = item.type == _typeEpisode;
    final remainingMs = (item.duration ?? 0) - (item.viewOffset ?? 0);
    final progress = progressFraction(item);

    return SizedBox(
      height: _heroHeight.du(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _heroBackdropWidthFraction,
              heightFactor: 1,
              child: Artwork(
                imageUrl: PlexImageUrl.of(server, item.art ?? item.thumb),
                noiseOpacity: 0.3,
              ),
            ),
          ),
          // scrim.edge — the ground colour holds solid under the text
          // column and fades away toward the artwork. DESIGN.md #2.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.edge),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.bottom),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xxxl.du(context),
              AppSpacing.xxxl.du(context),
              AppSpacing.xxxl.du(context),
              AppSpacing.xl.du(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 20.du(context), height: 2.du(context), color: AppColors.accent),
                    SizedBox(width: AppSpacing.md.du(context)),
                    AppText('RESUME', style: AppTypography.micro),
                  ],
                ),
                SizedBox(height: AppSpacing.md.du(context)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 900.du(context)),
                  child: AppText(
                    continueWatchingTitle(item),
                    style: AppTypography.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isEpisode) ...[
                  SizedBox(height: AppSpacing.sm.du(context)),
                  AppText(
                    item.parentIndex != null && item.index != null
                        ? 'Season ${item.parentIndex}, Episode ${item.index} · ${item.title}'
                        : item.title,
                    color: AppColors.ink2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (remainingMs > 0) ...[
                  SizedBox(height: AppSpacing.md.du(context)),
                  Row(
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _progressBarWidth.du(context),
                          ),
                          child: SizedBox(
                            height: 4.du(context),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.ink.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(2.du(context)),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: AppSpacing.lg.du(context)),
                      // The remaining-time label carries the information the
                      // bar only visualizes, so it keeps its natural width
                      // (never truncates) and the decorative bar is what
                      // yields if the row is ever tighter than bar+label.
                      AppText(
                        formatMinutesLeft(remainingMs),
                        color: AppColors.ink2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
                SizedBox(height: AppSpacing.lg.du(context)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      onClick: onResume,
                      focusNode: resumeFocusNode,
                      autofocus: autofocus,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(PhosphorIconsFill.play, size: 22),
                          SizedBox(width: AppSpacing.sm.du(context)),
                          const AppText('Resume'),
                        ],
                      ),
                    ),
                    if (onWatchTogether != null) ...[
                      SizedBox(width: AppSpacing.md.du(context)),
                      AppOutlinedButton(
                        onClick: () => onWatchTogether!(item),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(PhosphorIconsRegular.usersThree, size: 22),
                            SizedBox(width: AppSpacing.sm.du(context)),
                            const AppText('Watch Together'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
