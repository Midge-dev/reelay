import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ServerReachability;
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watch_together_icon.dart';
import '../common/watchlist_button.dart';
import 'movie_detail_sections.dart';
import 'source_picker_dialog.dart';

const _heroHeight = 680.0;
const _posterWidth = 280.0;
const _posterHeight = 420.0;
final _restartButtonBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/library/MovieDetailScreen.kt. The hero's action buttons each
/// call [_scrollToTop] directly from their own onFocusChange — Kotlin
/// needs a "heroFocusToken" int (not a boolean) specifically because
/// Compose's `LaunchedEffect(key)` only re-fires when its key actually
/// *changes*, so a boolean flipping true->true between two already-
/// focused-region buttons never re-triggers (ARCHITECTURE.md §4,
/// checklist item #6). Flutter's onFocusChange is an imperative callback
/// invoked unconditionally every time focus changes, so it re-fires on
/// every move between action buttons with no token workaround needed —
/// the hazard is specific to Compose's effect-dedup, not a Flutter one.
class MovieDetailScreen extends StatefulWidget {
  final PlexServer server;
  final PlexLibraryItem movie;
  final FoldedWork<PlexLibraryItem> work;
  final VoidCallback onBack;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onWatchTogether;
  final ValueChanged<String> onRestartSolo;
  final bool Function(String?) isOnWatchlist;
  final ValueChanged<String?> onToggleWatchlist;
  final Future<PlexMovieDetail?> Function() loadDetail;
  final Future<List<PlexHub>> Function() loadRelatedHubs;
  final Future<List<PlexLibraryItem>> Function(int actorId) loadByActor;
  final ValueChanged<PlexOnDeckItem> onSelectRelated;
  final ValueChanged<PlexPerson> onSelectPerson;
  final ValueChanged<Sourced<PlexLibraryItem>> onSwitchSource;

  const MovieDetailScreen({
    super.key,
    required this.server,
    required this.movie,
    required this.work,
    required this.onBack,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onRestartSolo,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.loadDetail,
    required this.loadRelatedHubs,
    required this.loadByActor,
    required this.onSelectRelated,
    required this.onSelectPerson,
    required this.onSwitchSource,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _CoStarRow {
  final PlexPerson person;
  final List<PlexLibraryItem> items;

  const _CoStarRow(this.person, this.items);
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final _playFocus = FocusNode(debugLabel: 'movie-detail-play');
  final _scrollController = ScrollController();

  PlexMovieDetail? _detail;
  List<PlexHub> _relatedHubs = const [];
  List<_CoStarRow> _coStarRows = const [];
  bool _showingSourcePicker = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _playFocus.requestFocus(),
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant MovieDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.ratingKey != widget.movie.ratingKey) {
      setState(() {
        _detail = null;
        _relatedHubs = const [];
        _coStarRows = const [];
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _playFocus.requestFocus(),
      );
      _load();
    }
  }

  @override
  void dispose() {
    _playFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.loadDetail(),
      widget.loadRelatedHubs(),
    ]);
    if (!mounted) return;
    final detail = results[0] as PlexMovieDetail?;
    final relatedHubs = results[1] as List<PlexHub>;
    setState(() {
      _detail = detail;
      _relatedHubs = relatedHubs;
    });
    await _computeCoStarRows(detail, relatedHubs);
  }

  Future<void> _computeCoStarRows(
    PlexMovieDetail? detail,
    List<PlexHub> relatedHubs,
  ) async {
    final roles = detail?.roles;
    if (roles == null) return;

    final autoHubNames = <String>{};
    for (final hub in relatedHubs) {
      const prefix = 'More with ';
      if (hub.title.startsWith(prefix))
        autoHubNames.add(hub.title.substring(prefix.length));
    }

    final seen = <Object>{};
    final candidates = <PlexPerson>[];
    for (final person in roles) {
      if (autoHubNames.contains(person.tag)) continue;
      final identity = person.id ?? person.tag;
      if (!seen.add(identity)) continue;
      candidates.add(person);
      if (candidates.length >= 2) break;
    }

    final rows = <_CoStarRow>[];
    for (final person in candidates) {
      final actorId = person.id;
      if (actorId == null) continue;
      final items = (await widget.loadByActor(actorId))
          .where((i) => i.ratingKey != widget.movie.ratingKey)
          .toList();
      if (items.length >= 3) rows.add(_CoStarRow(person, items));
    }
    if (mounted) setState(() => _coStarRows = rows);
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final hasResume = (detail?.viewOffset ?? 0) > 0;
    final playLabel = hasResume ? 'Continue' : 'Play';
    final watchTogetherLabel = hasResume
        ? 'Continue Together'
        : 'Watch Together';

    final sections = <Widget>[
      _MovieHero(
        server: widget.server,
        movie: widget.movie,
        summary: detail?.summary ?? widget.movie.summary,
        duration: detail?.duration,
        viewOffset: detail?.viewOffset,
        media: detail?.media.isNotEmpty == true ? detail!.media.first : null,
        playLabel: playLabel,
        watchTogetherLabel: watchTogetherLabel,
        showRestart: hasResume,
        playFocus: _playFocus,
        onPlay: () => widget.onPlay(widget.movie.ratingKey),
        onWatchTogether: () => widget.onWatchTogether(widget.movie.ratingKey),
        onRestartSolo: () => widget.onRestartSolo(widget.movie.ratingKey),
        isOnWatchlist: widget.isOnWatchlist(detail?.guid),
        onToggleWatchlist: () => widget.onToggleWatchlist(detail?.guid),
        onActionButtonFocused: _scrollToTop,
        copyCount: widget.work.copies.length,
        onOpenSourcePicker: widget.work.copies.length > 1
            ? () => setState(() => _showingSourcePicker = true)
            : null,
      ),
    ];
    if (detail != null) {
      sections.add(
        CastCrewRow(
          server: widget.server,
          cast: detail.roles,
          crew: [...detail.directors, ...detail.writers],
          onSelectPerson: widget.onSelectPerson,
        ),
      );
    }
    for (final hub in _relatedHubs) {
      sections.add(
        PosterRow(
          key: ValueKey(hub.hubIdentifier ?? hub.title),
          title: hub.title,
          items: hub.items
              .map((i) => FoldedWork(i.guid, [Sourced(i, widget.server, ServerReachability.local)]))
              .toList(),
          onClick: (item) => widget.onSelectRelated(item.primary.value),
        ),
      );
    }
    for (final row in _coStarRows) {
      sections.add(
        PosterRow(
          key: ValueKey(row.person.id ?? row.person.tag),
          title: 'More with ${row.person.tag}',
          items: row.items
              .map(
                (i) => FoldedWork(
                  i.guid,
                  [
                    Sourced(
                      PlexOnDeckItem(
                        ratingKey: i.ratingKey,
                        type: i.type ?? 'movie',
                        title: i.title,
                        thumb: i.thumb,
                        guid: i.guid,
                      ),
                      widget.server,
                      ServerReachability.local,
                    ),
                  ],
                ),
              )
              .toList(),
          onClick: (item) => widget.onSelectRelated(item.primary.value),
        ),
      );
    }
    sections.add(SizedBox(height: 48.du(context)));

    return Stack(
      children: [
        BackHandler(
          onBack: widget.onBack,
          child: ColoredBox(
            color: AppColors.background,
            child: ListView.separated(
              controller: _scrollController,
              itemCount: sections.length,
              separatorBuilder: (context, index) => SizedBox(height: 28.du(context)),
              itemBuilder: (context, index) => sections[index],
            ),
          ),
        ),
        if (_showingSourcePicker)
          SourcePickerDialog(
            title: widget.movie.title,
            work: widget.work,
            activeCopy: widget.work.copies.firstWhere(
              (c) => c.server.machineIdentifier == widget.server.machineIdentifier,
              orElse: () => widget.work.primary,
            ),
            onSelect: widget.onSwitchSource,
            onClose: () => setState(() => _showingSourcePicker = false),
          ),
      ],
    );
  }
}

class _MovieHero extends StatelessWidget {
  final PlexServer server;
  final PlexLibraryItem movie;
  final String? summary;
  final int? duration;
  final int? viewOffset;
  final PlexMedia? media;
  final String playLabel;
  final String watchTogetherLabel;
  final bool showRestart;
  final FocusNode playFocus;
  final VoidCallback onPlay;
  final VoidCallback onWatchTogether;
  final VoidCallback onRestartSolo;
  final bool isOnWatchlist;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onActionButtonFocused;
  final int copyCount;
  final VoidCallback? onOpenSourcePicker;

  const _MovieHero({
    required this.server,
    required this.movie,
    this.summary,
    this.duration,
    this.viewOffset,
    this.media,
    required this.playLabel,
    required this.watchTogetherLabel,
    required this.showRestart,
    required this.playFocus,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onRestartSolo,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.onActionButtonFocused,
    required this.copyCount,
    this.onOpenSourcePicker,
  });

  void _onFocus(bool focused) {
    if (focused) onActionButtonFocused();
  }

  // Nothing sits above the action button row (it's the top of the
  // hero) — without this, Flutter's default traversal treats the nav
  // rail's Home item as the nearest candidate in that direction and
  // escapes there, same class of bug as library_screen.dart's
  // _trapUpAboveTabs.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final remainingMs = (duration ?? 0) - (viewOffset ?? 0);
    final hasProgress = (viewOffset ?? 0) > 0 && remainingMs > 0;
    final progress = duration != null && duration! > 0
        ? ((viewOffset ?? 0) / duration!).clamp(0.0, 1.0)
        : 0.0;

    final metaParts = <String>[
      if (movie.year != null) '${movie.year}',
      if (duration != null) formatRuntime(duration!),
      if (movie.genres.isNotEmpty) movie.genres.first.tag,
    ];

    final sourceParts = <String>[
      server.name,
      if (media?.videoResolution != null) media!.videoResolution!.toUpperCase(),
      if (media?.videoCodec != null) media!.videoCodec!.toUpperCase(),
    ];

    return SizedBox(
      height: _heroHeight.du(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            imageUrl: PlexImageUrl.of(server, movie.art ?? movie.thumb),
            noiseOpacity: 0.3,
          ),
          // scrim.edge — the ground colour holds solid under the text
          // column and fades away toward the artwork. DESIGN.md #2.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.edge),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.bottom),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xxxl.du(context),
              AppSpacing.xxl.du(context),
              AppSpacing.xxxl.du(context),
              AppSpacing.xl.du(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
                  child: Container(
                    width: _posterWidth.du(context),
                    height: _posterHeight.du(context),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: Artwork(
                      imageUrl: PlexImageUrl.of(server, movie.thumb),
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.xxl.du(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20.du(context),
                            height: 2.du(context),
                            color: AppColors.accent,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText('MOVIE', style: AppTypography.micro),
                        ],
                      ),
                      SizedBox(height: AppSpacing.sm.du(context)),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 960.du(context)),
                        child: AppText(
                          movie.title,
                          style: AppTypography.display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (metaParts.isNotEmpty) ...[
                        SizedBox(height: AppSpacing.sm.du(context)),
                        AppText(metaParts.join(' · '), color: AppColors.ink2),
                      ],
                      if (hasProgress) ...[
                        SizedBox(height: AppSpacing.md.du(context)),
                        Row(
                          children: [
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 380.du(context),
                                ),
                                child: SizedBox(
                                  height: 4.du(context),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.ink.withValues(
                                        alpha: 0.22,
                                      ),
                                      borderRadius: BorderRadius.circular(2.du(context)),
                                    ),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: progress,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: AppSpacing.lg.du(context)),
                            // The remaining-time label carries the information the
                            // bar only visualizes, so it keeps its natural width
                            // (never truncates) and the decorative bar is what
                            // yields if the row is ever tighter than 380+label.
                            AppText(
                              formatMinutesLeft(remainingMs),
                              color: AppColors.ink2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                      if (summary != null) ...[
                        SizedBox(height: AppSpacing.md.du(context)),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 780.du(context)),
                          child: AppText(
                            summary!,
                            style: AppTypography.body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      SizedBox(height: AppSpacing.lg.du(context)),
                      Focus(
                        canRequestFocus: false,
                        onKeyEvent: _trapUp,
                        child: Wrap(
                          // Wrap, not Row — RoomCard in watch_together_row.dart
                          // hit the same problem: Watch Together plus the
                          // watchlist button can be wider than the column
                          // allows. Drops to a second line instead of
                          // hard-overflowing.
                          spacing: AppSpacing.md.du(context),
                          runSpacing: AppSpacing.md.du(context),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppButton(
                              onClick: onPlay,
                              focusNode: playFocus,
                              onFocusChange: _onFocus,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const AppIcon(
                                    PhosphorIconsFill.play,
                                    size: 22,
                                  ),
                                  SizedBox(width: AppSpacing.sm.du(context)),
                                  AppText(playLabel),
                                ],
                              ),
                            ),
                            AppOutlinedButton(
                              onClick: onWatchTogether,
                              onFocusChange: _onFocus,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const WatchTogetherIcon(),
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: AppSpacing.sm.du(context),
                                    ),
                                    child: AppText(watchTogetherLabel),
                                  ),
                                ],
                              ),
                            ),
                            if (showRestart)
                              AppIconButton(
                                onClick: onRestartSolo,
                                border: _restartButtonBorder,
                                onFocusChange: _onFocus,
                                child: const AppIcon(
                                  PhosphorIconsRegular.arrowCounterClockwise,
                                ),
                              ),
                            WatchlistButton(
                              isOnWatchlist: isOnWatchlist,
                              onClick: onToggleWatchlist,
                              onFocusChange: _onFocus,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.lg.du(context)),
                      _SourceChip(
                        sourceParts: sourceParts,
                        copyCount: copyCount,
                        onClick: onOpenSourcePicker,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _sourceChipBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Screen 03's "Playing from Attic · 4K HDR | 3 copies >" chip — plain text
/// when there's only one copy (nothing to disambiguate), a focusable
/// surface opening [SourcePickerDialog] (screen 03d) once [onClick] is
/// non-null, i.e. once folding actually found more than one.
class _SourceChip extends StatelessWidget {
  final List<String> sourceParts;
  final int copyCount;
  final VoidCallback? onClick;

  const _SourceChip({
    required this.sourceParts,
    required this.copyCount,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.du(context),
          height: 8.du(context),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success,
          ),
        ),
        SizedBox(width: AppSpacing.md.du(context)),
        AppText('Playing from ${sourceParts.join(' · ')}', color: AppColors.ink2),
        if (onClick != null) ...[
          SizedBox(width: AppSpacing.md.du(context)),
          Container(width: 1.du(context), height: 26.du(context), color: AppColors.line),
          SizedBox(width: AppSpacing.md.du(context)),
          AppText('$copyCount copies', color: AppColors.ink3),
          SizedBox(width: AppSpacing.sm.du(context)),
          AppIcon(PhosphorIconsRegular.caretRight, size: 18, tint: AppColors.ink4),
        ],
      ],
    );

    if (onClick == null) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg.du(context),
          vertical: AppSpacing.sm.du(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        child: content,
      );
    }

    return AppCard(
      onClick: onClick!,
      border: _sourceChipBorder,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg.du(context),
          vertical: AppSpacing.sm.du(context),
        ),
        child: content,
      ),
    );
  }
}
