import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import 'poster_card.dart';

/// Ports ui/library/PersonFilmographyScreen.kt.
class PersonFilmographyScreen extends StatelessWidget {
  final PlexServer server;
  final String personName;
  final String? personThumb;
  final List<PlexLibraryItem> items;
  final ValueChanged<PlexLibraryItem> onSelectItem;
  final VoidCallback onBack;

  const PersonFilmographyScreen({
    super.key,
    required this.server,
    required this.personName,
    this.personThumb,
    required this.items,
    required this.onSelectItem,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final thumbUrl = personThumb != null
        ? PlexImageUrl.of(server, personThumb)
        : null;

    return BackHandler(
      onBack: onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 32.du(context),
                top: 32.du(context),
                right: 32.du(context),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 88.du(context),
                      height: 88.du(context),
                      child: thumbUrl != null
                          ? Artwork(imageUrl: thumbUrl)
                          : ColoredBox(
                              color: AppColors.accent.withValues(alpha: 0.35),
                              child: Center(
                                child: AppText(
                                  personName.isNotEmpty
                                      ? personName[0].toUpperCase()
                                      : '?',
                                  style: AppTypography.title1,
                                  color: AppColors.inkOnArt,
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: 20.du(context)),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppText(
                          personName,
                          style: AppTypography.title1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4.du(context)),
                        AppText(
                          '${items.length} title${items.length == 1 ? '' : 's'} in your library',
                          color: AppColors.ink3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.safeX.du(context),
                ),
                child: PosterGrid(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return PosterCard(
                      key: ValueKey(item.ratingKey),
                      imageUrl: PlexImageUrl.of(server, item.thumb),
                      title: item.title,
                      autofocus: index == 0,
                      onClick: () => onSelectItem(item),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
