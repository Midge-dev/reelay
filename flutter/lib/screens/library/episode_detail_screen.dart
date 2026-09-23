import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watchlist_button.dart';

SurfaceBorder get _restartButtonBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/library/EpisodeDetailScreen.kt.
class EpisodeDetailScreen extends StatefulWidget {
  final PlexServer server;
  final String showTitle;
  final PlexEpisode episode;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromStart;
  final VoidCallback onWatchTogether;
  final VoidCallback onRestartTogether;
  final bool Function(String?) isOnWatchlist;
  final ValueChanged<String?> onToggleWatchlist;
  final Future<String?> Function() loadShowGuid;

  const EpisodeDetailScreen({
    super.key,
    required this.server,
    required this.showTitle,
    required this.episode,
    required this.onBack,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onWatchTogether,
    required this.onRestartTogether,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.loadShowGuid,
  });

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  final _primaryFocus = FocusNode(debugLabel: 'episode-detail-primary');
  String? _showGuid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _primaryFocus.requestFocus(),
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant EpisodeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.ratingKey != widget.episode.ratingKey) {
      setState(() => _showGuid = null);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _primaryFocus.requestFocus(),
      );
      _load();
    }
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
    super.dispose();
  }

  // Nothing sits above the action button row (it's the top of the
  // hero) — without this, Flutter's default traversal treats the nav
  // rail's Home item as the nearest candidate in that direction and
  // escapes there, same class of bug as library_screen.dart's
  // _trapUpAboveTabs.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _load() async {
    final guid = await widget.loadShowGuid();
    if (mounted) setState(() => _showGuid = guid);
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final hasResume = (episode.viewOffset ?? 0) > 0;
    final remainingMs = (episode.duration ?? 0) - (episode.viewOffset ?? 0);
    final hasProgress = hasResume && remainingMs > 0;
    final progress = episode.duration != null && episode.duration! > 0
        ? ((episode.viewOffset ?? 0) / episode.duration!).clamp(0.0, 1.0)
        : 0.0;

    final kickerParts = [widget.showTitle];
    if (episode.parentIndex != null)
      kickerParts.add('Season ${episode.parentIndex}');
    if (episode.index != null) kickerParts.add('Episode ${episode.index}');

    final metaParts = <String>[
      if (episode.originallyAvailableAt != null)
        formatAirDate(episode.originallyAvailableAt!),
      if (episode.duration != null) formatRuntime(episode.duration!),
    ];

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(imageUrl: PlexImageUrl.of(widget.server, episode.thumb)),
              // scrim.edge — the ground colour holds solid under the text
              // column and fades away toward the artwork. DESIGN.md #2.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppScrims.edge),
                ),
              ),
              Padding(
                // The same frame as the show page it came from (screen
                // 04): 80 du from the top, 48 from the rail.
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.safeX.du(context),
                  80.du(context),
                  80.du(context),
                  AppSpacing.safeY.du(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
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
                        AppText(
                          kickerParts.join(' · ').toUpperCase(),
                          style: AppTypography.micro,
                        ),
                      ],
                    ),
                    SizedBox(height: 14.du(context)),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 820.du(context)),
                      child: AppText(
                        episode.title,
                        color: AppColors.inkOnArt,
                        style: AppTypography.display,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (metaParts.isNotEmpty) ...[
                      SizedBox(height: 14.du(context)),
                      AppText(
                        metaParts.join('  ·  '),
                        style: AppTypography.caption,
                        color: AppColors.ink2,
                      ),
                    ],
                    if (hasProgress) ...[
                      SizedBox(height: AppSpacing.md.du(context)),
                      Row(
                        children: [
                          Flexible(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 380.du(context),
                              ),
                              child: SizedBox(
                                height: 4.du(context),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.ink.withValues(
                                      alpha: 0.22,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      2.du(context),
                                    ),
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
                          // yields if the row is ever tighter than 380+label.
                          AppText(
                            formatMinutesLeft(remainingMs),
                            color: AppColors.ink2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                    if (episode.summary != null) ...[
                      SizedBox(height: AppSpacing.md.du(context)),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 780.du(context)),
                        child: AppText(
                          episode.summary!,
                          style: AppTypography.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    SizedBox(height: AppSpacing.lg.du(context)),
                    Focus(
                      canRequestFocus: false,
                      onKeyEvent: _trapUp,
                      child: Wrap(
                        // Wrap, not Row — see the matching comment on
                        // movie_detail_screen.dart's action row and RoomCard
                        // in watch_together_row.dart. A resumed episode adds
                        // a fourth and fifth button (Play from start,
                        // restart) that can be wider than the column allows.
                        spacing: AppSpacing.md.du(context),
                        runSpacing: AppSpacing.md.du(context),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppButton(
                            onClick: widget.onPlay,
                            focusNode: _primaryFocus,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(PhosphorIconsFill.play, size: 22),
                                SizedBox(width: AppSpacing.md.du(context)),
                                AppText(
                                  hasResume
                                      ? 'Resume ${formatTimecode(episode.viewOffset ?? 0)}'
                                      : 'Play',
                                  style: AppTypography.label,
                                  color: null,
                                ),
                              ],
                            ),
                          ),
                          if (hasResume)
                            AppOutlinedButton(
                              onClick: widget.onPlayFromStart,
                              child: const AppText('Play from start'),
                            ),
                          AppOutlinedButton(
                            onClick: widget.onWatchTogether,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  PhosphorIconsRegular.usersThree,
                                  size: 22,
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: AppSpacing.sm.du(context),
                                  ),
                                  child: AppText(
                                    hasResume
                                        ? 'Continue Together'
                                        : 'Watch Together',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          WatchlistButton(
                            isOnWatchlist: widget.isOnWatchlist(_showGuid),
                            onClick: () => widget.onToggleWatchlist(_showGuid),
                          ),
                          if (hasResume)
                            AppIconButton(
                              onClick: widget.onRestartTogether,
                              border: _restartButtonBorder,
                              child: const AppIcon(
                                PhosphorIconsRegular.arrowCounterClockwise,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
