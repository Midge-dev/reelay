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
class ShowSeasonsScreen extends StatefulWidget {
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
  State<ShowSeasonsScreen> createState() => _ShowSeasonsScreenState();
}

class _ShowSeasonsScreenState extends State<ShowSeasonsScreen> {
  final _firstPosterFocusNode = FocusNode(debugLabel: 'show-seasons-first-poster');

  @override
  void initState() {
    super.initState();
    // Explicit, not autofocus: this screen replaces the detail screen in the
    // same frame its "Seasons" button (which held focus) is disposed —
    // Flutter's autofocus declines to steal focus from an already-focused
    // scope in that race, leaving focus to fall back to the nav drawer's
    // rail instead (same root cause as the player controls bar fix).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstPosterFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstPosterFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final showTitle = widget.showTitle;
    final seasons = widget.seasons;
    final onSelect = widget.onSelect;
    final onBack = widget.onBack;
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
                    focusNode: index == 0 ? _firstPosterFocusNode : null,
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
