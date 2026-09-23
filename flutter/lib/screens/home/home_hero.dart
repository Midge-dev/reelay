import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import 'home_posters.dart';

const _typeEpisode = 'episode';

// Screen 01, first viewport: backdrop 1180 du wide on the right, full
// height; text column from 120 du down, 18 du between blocks, capped at
// 960 du; synopsis 660 du; a 560 du bottom fade into the ground that the
// Watch Together bar and "More in progress" sit on.
const _backdropWidth = 1180.0;
const _heroTopInset = 120.0;
const _heroBlockGap = 18.0;
const _heroTextMaxWidth = 960.0;
const _synopsisMaxWidth = 660.0;
const _bottomFadeHeight = 560.0;
const _progressBarWidth = 380.0;
const _footerGap = 28.0;

/// The resume hero — screen 01's opening viewport: the top in-progress
/// item (real data, no invented curation) over its backdrop, with the
/// Watch Together bar and the "More in progress" row as its [footer],
/// pinned to the bottom of the same viewport. At least one viewport tall —
/// taller only when the UI Size setting makes the 1080 du layout not fit,
/// in which case the footer simply continues below the fold.
///
/// No Episodes action — that needs the parent show's own ratingKey, which
/// [PlexOnDeckItem] doesn't carry — and no restart action, since the detail
/// screen this hero's Resume reaches already has one.
class HomeHero extends StatelessWidget {
  final FoldedWork<PlexOnDeckItem> item;
  final double height;
  final VoidCallback onResume;
  final ValueChanged<Sourced<PlexOnDeckItem>>? onWatchTogether;
  final FocusNode? resumeFocusNode;
  final bool autofocus;
  final List<Widget> footer;

  /// Focus arrived on one of the hero's own actions (not the footer rows)
  /// — Home scrolls back to the very top so the whole hero shows.
  final VoidCallback? onActionsFocused;

  const HomeHero({
    super.key,
    required this.item,
    required this.height,
    required this.onResume,
    this.onWatchTogether,
    this.resumeFocusNode,
    this.autofocus = false,
    this.footer = const [],
    this.onActionsFocused,
  });

  @override
  Widget build(BuildContext context) {
    final active = item.primary;
    final value = active.value;
    final isEpisode = value.type == _typeEpisode;
    final remainingMs = (value.duration ?? 0) - (value.viewOffset ?? 0);
    final progress = progressFraction(value);
    final gap = SizedBox(height: _heroBlockGap.du(context));
    final summary = value.summary?.trim();
    final meta = [
      if (isEpisode && value.parentIndex != null && value.index != null)
        'Season ${value.parentIndex}, Episode ${value.index}',
      if (isEpisode) value.title,
      active.server.name,
    ];

    // At least a viewport tall: the Stack passes the min height straight to
    // the Column, whose spaceBetween pushes the footer to the bottom of it —
    // or, when the content is taller (a large UI Size), simply stacks it.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _backdropWidth.du(context),
            child: Artwork(
              imageUrl: PlexImageUrl.of(
                active.server,
                value.art ?? value.thumb,
              ),
            ),
          ),
          // scrim.edge — the ground holds solid under the text column and
          // fades toward the artwork. DESIGN.md #2.
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _backdropWidth.du(context),
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.edge),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _bottomFadeHeight.du(context),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background,
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.safeX.du(context),
                  _heroTopInset.du(context),
                  AppSpacing.safeX.du(context),
                  0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _heroTextMaxWidth.du(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20.du(context),
                            height: 2.du(context),
                            color: AppColors.accent,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText('RESUME', style: AppTypography.micro),
                        ],
                      ),
                      gap,
                      AppText(
                        continueWatchingTitle(value),
                        style: AppTypography.display,
                        color: AppColors.inkOnArt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      gap,
                      AppText(
                        meta.join('  ·  '),
                        style: AppTypography.caption,
                        color: AppColors.ink2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (remainingMs > 0) ...[
                        gap,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                2.du(context),
                              ),
                              child: SizedBox(
                                width: _progressBarWidth.du(context),
                                height: AppSpacing.xs.du(context),
                                child: ColoredBox(
                                  color: AppColors.ink.withValues(alpha: 0.22),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: ColoredBox(color: AppColors.accent),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: AppSpacing.lg.du(context)),
                            AppText(
                              formatMinutesLeft(remainingMs),
                              style: AppTypography.caption,
                              color: AppColors.ink2,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ],
                      if (summary != null && summary.isNotEmpty) ...[
                        gap,
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _synopsisMaxWidth.du(context),
                          ),
                          child: AppText(
                            summary,
                            style: AppTypography.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      SizedBox(height: (_heroBlockGap + 10).du(context)),
                      Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (focused) {
                          if (focused) onActionsFocused?.call();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppButton(
                              onClick: onResume,
                              focusNode: resumeFocusNode,
                              autofocus: autofocus,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const AppIcon(
                                    PhosphorIconsFill.play,
                                    size: 22,
                                  ),
                                  SizedBox(width: AppSpacing.md.du(context)),
                                  const AppText('Resume'),
                                ],
                              ),
                            ),
                            if (onWatchTogether != null) ...[
                              SizedBox(width: AppSpacing.lg.du(context)),
                              AppOutlinedButton(
                                onClick: () => onWatchTogether!(active),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const AppIcon(
                                      PhosphorIconsRegular.usersThree,
                                      size: 22,
                                    ),
                                    SizedBox(width: AppSpacing.md.du(context)),
                                    const AppText('Watch Together'),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: _footerGap.du(context)),
                  for (final (i, w) in footer.indexed) ...[
                    if (i > 0) SizedBox(height: _footerGap.du(context)),
                    w,
                  ],
                  SizedBox(height: AppSpacing.safeY.du(context)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
