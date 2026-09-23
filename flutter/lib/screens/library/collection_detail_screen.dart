import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'poster_card.dart';

/// Ports ui/library/CollectionDetailScreen.kt.
class CollectionDetailScreen extends StatelessWidget {
  final PlexServer server;
  final PlexCollection collection;
  final List<PlexLibraryItem> items;
  final ValueChanged<PlexLibraryItem> onSelectItem;
  final VoidCallback onBack;

  const CollectionDetailScreen({
    super.key,
    required this.server,
    required this.collection,
    required this.items,
    required this.onSelectItem,
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
              padding: EdgeInsets.only(
                left: 32.du(context),
                top: 32.du(context),
                right: 32.du(context),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(collection.title, style: AppTypography.title1),
                  SizedBox(width: 16.du(context)),
                  AppText(
                    '${items.length} title${items.length == 1 ? '' : 's'}',
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(32.du(context)),
                      child: const AppText(
                        'No titles found in this collection.',
                      ),
                    )
                  : Padding(
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
