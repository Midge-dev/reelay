import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/screen_memory.dart';
import '../../focus/row_end_stop.dart';
import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

/// "2025 · 1h 58m · Drama [PG-13] [4K HDR] [TrueHD 7.1]" — 19 du ink2 with
/// ink4 separators, and the rating and media facts each in an outlined
/// chip (screens 03/04).
class MetaRow extends StatelessWidget {
  final List<String> parts;
  final List<String> chips;

  const MetaRow({super.key, required this.parts, this.chips = const []});

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(width: AppSpacing.lg.du(context));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.sm.du(context),
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0) ...[
            gap,
            AppText('·', style: AppTypography.caption, color: AppColors.ink4),
            gap,
          ],
          AppText(part, style: AppTypography.caption, color: AppColors.ink2),
        ],
        for (final chip in chips) ...[
          gap,
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 9.du(context),
              vertical: 3.du(context),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppShape.radiusSm.du(context),
              ),
              border: Border.all(
                color: AppColors.lineStrong,
                width: 1.du(context),
              ),
            ),
            child: AppText(
              chip,
              style: AppTypography.micro.copyWith(letterSpacing: 0),
              color: AppColors.ink2,
            ),
          ),
        ],
      ],
    );
  }
}

/// A row's heading with its one-line hint beside it on the baseline —
/// "Cast & crew · Select a name for everything they are in on your
/// servers" (screen 03).
class RowHeading extends StatelessWidget {
  final String title;
  final String? hint;

  const RowHeading({super.key, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.safeX.du(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          AppText(title, style: AppTypography.rowLabel),
          if (hint != null) ...[
            SizedBox(width: 22.du(context)),
            Flexible(
              child: AppText(
                hint!,
                style: AppTypography.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _personCircle = 130.0;
const _personWidth = 150.0;
const _personGap = 40.0;

/// Screen 03's Cast & crew: 130 du circles 40 apart, name and role under
/// each, and the crew after a hairline divider. Selecting a name opens
/// everything they are in on your servers (03c).
class CastCrewRow extends StatelessWidget {
  final PlexServer server;
  final List<PlexPerson> cast;
  final List<PlexPerson> directors;
  final List<PlexPerson> writers;
  final ValueChanged<PlexPerson> onSelectPerson;

  const CastCrewRow({
    super.key,
    required this.server,
    required this.cast,
    this.directors = const [],
    this.writers = const [],
    required this.onSelectPerson,
  });

  @override
  Widget build(BuildContext context) {
    // Someone who both directed and wrote appears once, as director.
    final seenCrew = <String>{};
    final crewEntries = <(PlexPerson, String)>[
      for (final p in directors)
        if (seenCrew.add(p.tag)) (p, 'Director'),
      for (final p in writers)
        if (seenCrew.add(p.tag)) (p, 'Writer'),
    ];
    if (cast.isEmpty && crewEntries.isEmpty) return const SizedBox.shrink();
    final entries = <Widget>[
      for (final person in cast)
        RememberFocus(
          key: ValueKey('cast-${person.id ?? person.tag}'),
          id: 'cast-${person.id ?? person.tag}',
          child: _CastMemberAvatar(
            server: server,
            person: person,
            subtitle: person.role,
            onClick: () => onSelectPerson(person),
          ),
        ),
      if (cast.isNotEmpty && crewEntries.isNotEmpty)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs.du(context)),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 1.du(context),
              height: _personCircle.du(context),
              color: AppColors.line,
            ),
          ),
        ),
      for (final (person, job) in crewEntries)
        RememberFocus(
          key: ValueKey('crew-${person.id ?? person.tag}'),
          id: 'crew-${person.id ?? person.tag}',
          child: _CastMemberAvatar(
            server: server,
            person: person,
            subtitle: job,
            onClick: () => onSelectPerson(person),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const RowHeading(
          title: 'Cast & crew',
          hint: 'Select a name for everything they are in on your servers',
        ),
        SizedBox(
          height: (AppSpacing.lg - AppSpacing.rowHeadroom / 2).du(context),
        ),
        SizedBox(
          // 130 circle + 10 + name 26 + role 24, +8 for text rounding at
          // fractional scales, + rowHeadroom for the focused circle.
          height: (_personCircle + 10 + 26 + 24 + 8 + AppSpacing.rowHeadroom)
              .du(context),
          child: EdgeFadeRow(
            child: RowEndStop(
              child: ListView.separated(
                key: const PageStorageKey('cast-crew'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.safeX.du(context),
                  vertical: (AppSpacing.rowHeadroom / 2).du(context),
                ),
                itemCount: entries.length,
                separatorBuilder: (context, index) => SizedBox(
                  width: (_personGap - (_personWidth - _personCircle)).du(
                    context,
                  ),
                ),
                itemBuilder: (context, index) => entries[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

SurfaceBorder get _personBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong, width: 1),
  focused: SurfaceBorderSide.solid(
    AppColors.accent,
    width: AppShape.artFrameWidth,
  ),
  noSpine: true,
);

class _CastMemberAvatar extends StatefulWidget {
  final PlexServer server;
  final PlexPerson person;
  final String? subtitle;
  final VoidCallback onClick;

  const _CastMemberAvatar({
    required this.server,
    required this.person,
    this.subtitle,
    required this.onClick,
  });

  @override
  State<_CastMemberAvatar> createState() => _CastMemberAvatarState();
}

class _CastMemberAvatarState extends State<_CastMemberAvatar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    return SizedBox(
      width: _personWidth.du(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: _personCircle.du(context),
            child: AppCard(
              onClick: widget.onClick,
              shape: const CircleBorder(),
              border: _personBorder,
              onFocusChange: (f) => setState(() => _focused = f),
              child: person.thumb != null
                  ? SizedBox.expand(
                      child: Artwork(
                        imageUrl: PlexImageUrl.of(widget.server, person.thumb),
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
                          color: AppColors.ink2,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(height: 10.du(context)),
          AppText(
            person.tag,
            style: AppTypography.label.copyWith(
              fontWeight: _focused ? FontWeight.w500 : FontWeight.w400,
            ),
            color: _focused ? AppColors.ink : AppColors.ink2,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (widget.subtitle != null)
            AppText(
              widget.subtitle!,
              style: AppTypography.caption,
              color: _focused ? AppColors.ink2 : AppColors.ink3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
