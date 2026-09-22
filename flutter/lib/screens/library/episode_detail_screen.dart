import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watch_together_icon.dart';
import '../common/watchlist_button.dart';

const _heroHeight = 710.0;
const _restartButtonBorder = SurfaceBorder(
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _primaryFocus.requestFocus());
    _load();
  }

  @override
  void didUpdateWidget(covariant EpisodeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.ratingKey != widget.episode.ratingKey) {
      setState(() => _showGuid = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => _primaryFocus.requestFocus());
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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
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
    final progress = episode.duration != null && episode.duration! > 0 ? ((episode.viewOffset ?? 0) / episode.duration!).clamp(0.0, 1.0) : 0.0;

    final kickerParts = [widget.showTitle];
    if (episode.parentIndex != null) kickerParts.add('Season ${episode.parentIndex}');
    if (episode.index != null) kickerParts.add('Episode ${episode.index}');

    final metaParts = <String>[
      if (episode.originallyAvailableAt != null) episode.originallyAvailableAt!,
      if (episode.duration != null) formatRuntime(episode.duration!),
    ];

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: SizedBox(
          height: _heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(imageUrl: PlexImageUrl.of(widget.server, episode.thumb), noiseOpacity: 0.3),
              // scrim.edge — the ground colour holds solid under the text
              // column and fades away toward the artwork. DESIGN.md #2.
              const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppScrims.edge))),
              const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppScrims.bottom))),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 20, height: 2, color: AppColors.accent),
                        const SizedBox(width: AppSpacing.md),
                        AppText(kickerParts.join(' · ').toUpperCase(), style: AppTypography.micro),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: AppText(episode.title, style: AppTypography.display, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppText(metaParts.join(' · '), color: AppColors.ink2),
                    ],
                    if (hasProgress) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: SizedBox(
                                height: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2)),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: const DecoratedBox(decoration: BoxDecoration(color: AppColors.accent)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          // The remaining-time label carries the information the
                          // bar only visualizes, so it keeps its natural width
                          // (never truncates) and the decorative bar is what
                          // yields if the row is ever tighter than 380+label.
                          AppText(formatMinutesLeft(remainingMs), color: AppColors.ink2, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ],
                    if (episode.summary != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: AppText(episode.summary!, style: AppTypography.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Focus(canRequestFocus: false, onKeyEvent: _trapUp, child: Wrap(
                      // Wrap, not Row — see the matching comment on
                      // movie_detail_screen.dart's action row and RoomCard
                      // in watch_together_row.dart. A resumed episode adds
                      // a fourth and fifth button (Play from start,
                      // restart) that can be wider than the column allows.
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppButton(
                          onClick: widget.onPlay,
                          focusNode: _primaryFocus,
                          child: AppText(hasResume ? 'Resume ${formatTimecode(episode.viewOffset ?? 0)}' : 'Play from start'),
                        ),
                        if (hasResume) AppOutlinedButton(onClick: widget.onPlayFromStart, child: const AppText('Play from start')),
                        AppOutlinedButton(
                          onClick: widget.onWatchTogether,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const WatchTogetherIcon(),
                            Padding(
                              padding: const EdgeInsets.only(left: AppSpacing.sm),
                              child: AppText(hasResume ? 'Continue Together' : 'Watch Together'),
                            ),
                          ]),
                        ),
                        WatchlistButton(
                          isOnWatchlist: widget.isOnWatchlist(_showGuid),
                          onClick: () => widget.onToggleWatchlist(_showGuid),
                        ),
                        if (hasResume) AppIconButton(onClick: widget.onRestartTogether, border: _restartButtonBorder, child: const AppIcon(Icons.replay)),
                      ],
                    )),
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
