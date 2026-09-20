import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/card.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

double _episodeProgressFraction(PlexEpisode episode) {
  final duration = episode.duration;
  if (duration == null || duration <= 0) return 0;
  final fraction = (episode.viewOffset ?? 0) / duration;
  return fraction.clamp(0.0, 1.0);
}

/// Ports ui/library/ShowEpisodesScreen.kt.
class ShowEpisodesScreen extends StatelessWidget {
  final PlexServer server;
  final String showTitle;
  final String seasonTitle;
  final List<PlexEpisode> episodes;
  final ValueChanged<PlexEpisode> onSelect;
  final VoidCallback onBack;

  const ShowEpisodesScreen({
    super.key,
    required this.server,
    required this.showTitle,
    required this.seasonTitle,
    required this.episodes,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 16, right: 32, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(showTitle, style: AppTypography.displaySmall),
                  AppText(seasonTitle, style: AppTypography.bodyLarge),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                // See the matching comment in collection_detail_screen.dart —
                // _EpisodeRow uses AppCard's focus-scale too.
                clipBehavior: Clip.none,
                itemCount: episodes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 24),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return _EpisodeRow(
                    key: ValueKey(episode.ratingKey),
                    server: server,
                    episode: episode,
                    autofocus: index == 0,
                    onClick: () => onSelect(episode),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final PlexServer server;
  final PlexEpisode episode;
  final bool autofocus;
  final VoidCallback onClick;

  const _EpisodeRow({super.key, required this.server, required this.episode, this.autofocus = false, required this.onClick});

  @override
  Widget build(BuildContext context) {
    final heading = episode.index != null ? '${episode.index}. ${episode.title}' : episode.title;
    final progress = _episodeProgressFraction(episode);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          height: 90,
          child: AppCard(
            onClick: onClick,
            autofocus: autofocus,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(imageUrl: PlexImageUrl.of(server, episode.thumb)),
                if (progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 4,
                      color: AppColors.scrim.withValues(alpha: 0.4),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(height: 4, color: AppColors.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(heading, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (episode.summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AppText(episode.summary!, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
