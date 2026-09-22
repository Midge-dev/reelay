import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'poster_card.dart';

const _gridColumns = 5;
const _posterCardHeight = 310.0; // 160w*3/2 image (240) + 16 padding + label line (26) + optional caption line (24)

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
              padding: EdgeInsets.only(left: 32.du(context), top: 32.du(context), right: 32.du(context)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(collection.title, style: AppTypography.title1),
                  SizedBox(width: 16.du(context)),
                  AppText('${items.length} title${items.length == 1 ? '' : 's'}', color: AppColors.ink3),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(32.du(context)),
                      child: const AppText('No titles found in this collection.'),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(32.du(context)),
                      // Flutter's GridView clips its children by default
                      // where Compose's grid doesn't — matters once a
                      // card's focus-scale can bleed past its own cell.
                      clipBehavior: Clip.none,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumns,
                        mainAxisSpacing: 24.du(context),
                        crossAxisSpacing: 24.du(context),
                        mainAxisExtent: _posterCardHeight.du(context),
                      ),
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
          ],
        ),
      ),
    );
  }
}
