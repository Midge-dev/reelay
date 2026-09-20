import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'poster_card.dart';

const _gridColumns = 5;
const _posterCardHeight = 278.0;

/// Ports ui/library/ShowSeasonsScreen.kt. `staggerDelayMs` (per-card noise
/// stagger) is carried through to PosterCard/Artwork even though Artwork
/// doesn't use it yet — see artwork.dart's note on the deferred noise
/// effect.
class ShowSeasonsScreen extends StatelessWidget {
  final PlexServer server;
  final String showTitle;
  final List<PlexSeason> seasons;
  final ValueChanged<PlexSeason> onSelect;
  final VoidCallback onBack;

  const ShowSeasonsScreen({
    super.key,
    required this.server,
    required this.showTitle,
    required this.seasons,
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
              child: AppText(showTitle, style: AppTypography.displaySmall),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(32),
                // See the matching comment in collection_detail_screen.dart.
                clipBehavior: Clip.none,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  mainAxisExtent: _posterCardHeight,
                ),
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  return PosterCard(
                    key: ValueKey(season.ratingKey),
                    imageUrl: PlexImageUrl.of(server, season.thumb),
                    title: season.title,
                    autofocus: index == 0,
                    staggerDelayMs: (index % _gridColumns) * 120,
                    onClick: () => onSelect(season),
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
