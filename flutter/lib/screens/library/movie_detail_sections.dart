import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

/// Ports ui/library/MovieDetailSections.kt's `CastCrewRow`.
class CastCrewRow extends StatelessWidget {
  final PlexServer server;
  final List<PlexPerson> cast;
  final List<PlexPerson> crew;
  final ValueChanged<PlexPerson> onSelectPerson;

  const CastCrewRow({
    super.key,
    required this.server,
    required this.cast,
    required this.crew,
    required this.onSelectPerson,
  });

  @override
  Widget build(BuildContext context) {
    final people = [...cast, ...crew];
    if (people.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xxxl,
            bottom: AppSpacing.lg,
          ),
          child: AppText('Cast & Crew', style: AppTypography.rowLabel),
        ),
        SizedBox(
          // See the matching comment on Continue Watching's SizedBox in
          // home_screen.dart — headroom for EdgeFadeRow's ShaderMask bounds.
          // Content height: 130 avatar + 10 padding + a label line (26) +
          // a 3px gap + a caption line (24), +24 headroom.
          height: 217,
          child: EdgeFadeRow(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Flutter's ListView clips its children by default where
              // Compose's LazyRow doesn't — matters once a card's focus-scale
              // can bleed past this SizedBox's fixed height.
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
              itemCount: people.length,
              separatorBuilder: (context, index) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final person = people[index];
                final subtitle =
                    person.role ?? (crew.contains(person) ? 'Crew' : null);
                return _CastMemberAvatar(
                  key: ValueKey(person.id ?? person.tag),
                  server: server,
                  person: person,
                  subtitle: subtitle,
                  onClick: () => onSelectPerson(person),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CastMemberAvatar extends StatelessWidget {
  final PlexServer server;
  final PlexPerson person;
  final String? subtitle;
  final VoidCallback onClick;

  const _CastMemberAvatar({
    super.key,
    required this.server,
    required this.person,
    this.subtitle,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    // Person circle 130 per DESIGN.md's geometry — label for the name,
    // caption/ink3 for the role, matching every other card's two-line
    // caption convention.
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: AppCard(
              onClick: onClick,
              shape: const CircleBorder(),
              child: person.thumb != null
                  ? SizedBox.expand(
                      child: Artwork(
                        imageUrl: PlexImageUrl.of(server, person.thumb),
                      ),
                    )
                  : ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                        child: AppText(
                          person.tag.isNotEmpty
                              ? person.tag[0].toUpperCase()
                              : '?',
                          style: AppTypography.title2,
                          color: AppColors.inkOnArt,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppText(
              person.tag,
              style: AppTypography.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AppText(
                subtitle!,
                style: AppTypography.caption,
                color: AppColors.ink3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ports ui/library/MovieDetailSections.kt's `PosterRow` — reused for
/// related-hub rows and co-star rows.
class PosterRow extends StatelessWidget {
  final String title;
  final List<PlexOnDeckItem> items;
  final PlexServer server;
  final ValueChanged<PlexOnDeckItem> onClick;

  const PosterRow({
    super.key,
    required this.title,
    required this.items,
    required this.server,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxxl,
            top: AppSpacing.xs,
            bottom: AppSpacing.lg,
          ),
          child: AppText(title, style: AppTypography.rowLabel),
        ),
        SizedBox(
          // Content height: 198 poster (132 wide, 2:3) + 10 padding + a
          // label line (26), +24 headroom.
          height: 258,
          child: EdgeFadeRow(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // See the matching comment on CastCrewRow above.
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final item = items[index];
                return _RelatedPoster(
                  key: ValueKey(item.ratingKey),
                  server: server,
                  item: item,
                  onClick: () => onClick(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

final _relatedPosterBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(
    AppColors.accent,
    width: AppShape.artFrameWidth,
  ),
  noSpine: true,
);

class _RelatedPoster extends StatelessWidget {
  final PlexServer server;
  final PlexOnDeckItem item;
  final VoidCallback onClick;

  const _RelatedPoster({
    super.key,
    required this.server,
    required this.item,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            // Artwork takes a frame all the way round instead of a spine —
            // a spine would cover the poster. DESIGN.md #3.
            child: AppCard(
              onClick: onClick,
              border: _relatedPosterBorder,
              child: SizedBox.expand(
                child: Artwork(imageUrl: PlexImageUrl.of(server, item.thumb)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppText(
              item.title,
              style: AppTypography.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
