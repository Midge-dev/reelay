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

const _heroHeight = 420.0;
const _restartButtonBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.dimBorder),
  focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient),
);
const _kickerStyle = TextStyle(fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w500, color: AppColors.accentGlow);

String _formatRuntime(int ms) {
  final totalMinutes = ms ~/ 60000;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

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
    final kickerParts = [widget.showTitle];
    if (episode.parentIndex != null) kickerParts.add('Season ${episode.parentIndex}');
    if (episode.index != null) kickerParts.add('Episode ${episode.index}');
    final kicker = kickerParts.join(' · ');

    final metaParts = <String>[];
    if (episode.originallyAvailableAt != null) metaParts.add(episode.originallyAvailableAt!);
    if (episode.duration != null) metaParts.add(_formatRuntime(episode.duration!));
    if (hasResume) {
      final remainingMs = (episode.duration ?? 0) - (episode.viewOffset ?? 0);
      if (remainingMs > 0) metaParts.add('${_formatRuntime(remainingMs)} left');
    }
    final metaLine = metaParts.join(' · ');

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: SizedBox(
          height: _heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Artwork(imageUrl: PlexImageUrl.of(widget.server, episode.thumb)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.35, 1],
                      colors: [AppColors.transparent, Color(0xCC000000), AppColors.scrim],
                    ),
                  ),
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(kicker, style: _kickerStyle),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AppText(episode.title, style: AppTypography.displaySmall, color: AppColors.white),
                      ),
                      if (metaLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AppText(metaLine, color: AppColors.white.withValues(alpha: 0.7)),
                        ),
                      if (episode.summary != null)
                        Padding(padding: const EdgeInsets.only(top: 16), child: AppText(episode.summary!, color: AppColors.white)),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Focus(canRequestFocus: false, onKeyEvent: _trapUp, child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppButton(
                              onClick: widget.onPlay,
                              focusNode: _primaryFocus,
                              child: AppText(hasResume ? 'Resume ${formatTimecode(episode.viewOffset ?? 0)}' : 'Play from start'),
                            ),
                            if (hasResume) ...[
                              const SizedBox(width: 16),
                              AppOutlinedButton(onClick: widget.onPlayFromStart, child: const AppText('Play from start')),
                            ],
                            const SizedBox(width: 16),
                            AppOutlinedButton(
                              onClick: widget.onWatchTogether,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const WatchTogetherIcon(),
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: AppText(hasResume ? 'Continue Together' : 'Watch Together'),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 16),
                            WatchlistButton(
                              isOnWatchlist: widget.isOnWatchlist(_showGuid),
                              onClick: () => widget.onToggleWatchlist(_showGuid),
                            ),
                            if (hasResume) ...[
                              const SizedBox(width: 16),
                              AppIconButton(
                                onClick: widget.onRestartTogether,
                                border: _restartButtonBorder,
                                child: const AppIcon(Icons.replay, tint: AppColors.white),
                              ),
                            ],
                          ],
                        )),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
