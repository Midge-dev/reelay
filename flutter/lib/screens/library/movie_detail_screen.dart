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
import 'movie_detail_sections.dart';

const _heroHeight = 560.0;
const _posterWidth = 280.0;
const _posterHeight = 420.0;
const _restartButtonBorder = SurfaceBorder(
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
  final bool isShow;
  final VoidCallback onBack;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onWatchTogether;
  final ValueChanged<String> onRestartSolo;
  final VoidCallback onSeasons;
  final bool Function(String?) isOnWatchlist;
  final ValueChanged<String?> onToggleWatchlist;
  final Future<PlexOnDeckItem?> Function() resolveNextEpisode;
  final Future<PlexMovieDetail?> Function() loadDetail;
  final Future<List<PlexHub>> Function() loadRelatedHubs;
  final Future<List<PlexLibraryItem>> Function(int actorId) loadByActor;
  final ValueChanged<PlexOnDeckItem> onSelectRelated;
  final ValueChanged<PlexPerson> onSelectPerson;

  const MovieDetailScreen({
    super.key,
    required this.server,
    required this.movie,
    required this.isShow,
    required this.onBack,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onRestartSolo,
    required this.onSeasons,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.resolveNextEpisode,
    required this.loadDetail,
    required this.loadRelatedHubs,
    required this.loadByActor,
    required this.onSelectRelated,
    required this.onSelectPerson,
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

  PlexOnDeckItem? _nextEpisode;
  PlexMovieDetail? _detail;
  List<PlexHub> _relatedHubs = const [];
  List<_CoStarRow> _coStarRows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playFocus.requestFocus());
    _load();
  }

  @override
  void didUpdateWidget(covariant MovieDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.ratingKey != widget.movie.ratingKey) {
      setState(() {
        _nextEpisode = null;
        _detail = null;
        _relatedHubs = const [];
        _coStarRows = const [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _playFocus.requestFocus());
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
    if (widget.isShow) {
      final next = await widget.resolveNextEpisode();
      if (mounted) setState(() => _nextEpisode = next);
    }
    final results = await Future.wait([widget.loadDetail(), widget.loadRelatedHubs()]);
    if (!mounted) return;
    final detail = results[0] as PlexMovieDetail?;
    final relatedHubs = results[1] as List<PlexHub>;
    setState(() {
      _detail = detail;
      _relatedHubs = relatedHubs;
    });
    await _computeCoStarRows(detail, relatedHubs);
  }

  Future<void> _computeCoStarRows(PlexMovieDetail? detail, List<PlexHub> relatedHubs) async {
    final roles = detail?.roles;
    if (roles == null) return;

    final autoHubNames = <String>{};
    for (final hub in relatedHubs) {
      const prefix = 'More with ';
      if (hub.title.startsWith(prefix)) autoHubNames.add(hub.title.substring(prefix.length));
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
      final items = (await widget.loadByActor(actorId)).where((i) => i.ratingKey != widget.movie.ratingKey).toList();
      if (items.length >= 3) rows.add(_CoStarRow(person, items));
    }
    if (mounted) setState(() => _coStarRows = rows);
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final hasResume = !widget.isShow && (detail?.viewOffset ?? 0) > 0;
    final playTarget = widget.isShow ? _nextEpisode?.ratingKey : widget.movie.ratingKey;
    final playLabel = widget.isShow
        ? (_nextEpisode != null ? 'Play S${_nextEpisode!.parentIndex}E${_nextEpisode!.index}' : 'Play')
        : (hasResume ? 'Continue' : 'Play');
    final watchTogetherLabel = hasResume ? 'Continue Together' : 'Watch Together';

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
        isShow: widget.isShow,
        onPlay: playTarget != null ? () => widget.onPlay(playTarget) : null,
        onWatchTogether: playTarget != null ? () => widget.onWatchTogether(playTarget) : null,
        onRestartSolo: playTarget != null ? () => widget.onRestartSolo(playTarget) : null,
        onSeasons: widget.onSeasons,
        isOnWatchlist: widget.isOnWatchlist(detail?.guid),
        onToggleWatchlist: () => widget.onToggleWatchlist(detail?.guid),
        onActionButtonFocused: _scrollToTop,
      ),
    ];
    if (detail != null) {
      sections.add(CastCrewRow(server: widget.server, cast: detail.roles, crew: [...detail.directors, ...detail.writers], onSelectPerson: widget.onSelectPerson));
    }
    for (final hub in _relatedHubs) {
      sections.add(PosterRow(
        key: ValueKey(hub.hubIdentifier ?? hub.title),
        title: hub.title,
        items: hub.items,
        server: widget.server,
        onClick: widget.onSelectRelated,
      ));
    }
    for (final row in _coStarRows) {
      sections.add(PosterRow(
        key: ValueKey(row.person.id ?? row.person.tag),
        title: 'More with ${row.person.tag}',
        items: row.items
            .map((i) => PlexOnDeckItem(ratingKey: i.ratingKey, type: i.type ?? 'movie', title: i.title, thumb: i.thumb))
            .toList(),
        server: widget.server,
        onClick: widget.onSelectRelated,
      ));
    }
    sections.add(const SizedBox(height: 48));

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: ListView.separated(
          controller: _scrollController,
          itemCount: sections.length,
          separatorBuilder: (context, index) => const SizedBox(height: 28),
          itemBuilder: (context, index) => sections[index],
        ),
      ),
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
  final bool isShow;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchTogether;
  final VoidCallback? onRestartSolo;
  final VoidCallback onSeasons;
  final bool isOnWatchlist;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onActionButtonFocused;

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
    required this.isShow,
    this.onPlay,
    this.onWatchTogether,
    this.onRestartSolo,
    required this.onSeasons,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.onActionButtonFocused,
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
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final remainingMs = (duration ?? 0) - (viewOffset ?? 0);
    final hasProgress = (viewOffset ?? 0) > 0 && remainingMs > 0;
    final progress = duration != null && duration! > 0 ? ((viewOffset ?? 0) / duration!).clamp(0.0, 1.0) : 0.0;

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
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(imageUrl: PlexImageUrl.of(server, movie.art ?? movie.thumb), noiseOpacity: 0.3),
          // scrim.edge — the ground colour holds solid under the text
          // column and fades away toward the artwork. DESIGN.md #2.
          const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppScrims.edge))),
          const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppScrims.bottom))),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppShape.radiusMd),
                  child: Container(
                    width: _posterWidth,
                    height: _posterHeight,
                    decoration: BoxDecoration(border: Border.all(color: AppColors.lineStrong)),
                    child: Artwork(imageUrl: PlexImageUrl.of(server, movie.thumb)),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 20, height: 2, color: AppColors.accent),
                          const SizedBox(width: AppSpacing.md),
                          AppText(isShow ? 'SHOW' : 'MOVIE', style: AppTypography.micro),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: AppText(movie.title, style: AppTypography.display, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AppText(metaParts.join(' · '), color: AppColors.ink2),
                      ],
                      if (hasProgress) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 380,
                              height: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2)),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: const DecoratedBox(decoration: BoxDecoration(color: AppColors.accent)),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            AppText(formatMinutesLeft(remainingMs), color: AppColors.ink2),
                          ],
                        ),
                      ],
                      if (summary != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 780),
                          child: AppText(summary!, style: AppTypography.body, maxLines: 4, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Focus(canRequestFocus: false, onKeyEvent: _trapUp, child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppButton(onClick: onPlay ?? () {}, focusNode: playFocus, onFocusChange: _onFocus, child: AppText(playLabel)),
                          const SizedBox(width: AppSpacing.md),
                          AppOutlinedButton(
                            onClick: onWatchTogether ?? () {},
                            onFocusChange: _onFocus,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const WatchTogetherIcon(),
                              Padding(padding: const EdgeInsets.only(left: AppSpacing.sm), child: AppText(watchTogetherLabel)),
                            ]),
                          ),
                          if (isShow) ...[
                            const SizedBox(width: AppSpacing.md),
                            AppOutlinedButton(onClick: onSeasons, onFocusChange: _onFocus, child: const AppText('Seasons')),
                          ],
                          if (showRestart) ...[
                            const SizedBox(width: AppSpacing.md),
                            AppIconButton(onClick: onRestartSolo ?? () {}, border: _restartButtonBorder, onFocusChange: _onFocus, child: const AppIcon(Icons.replay)),
                          ],
                          const SizedBox(width: AppSpacing.md),
                          WatchlistButton(isOnWatchlist: isOnWatchlist, onClick: onToggleWatchlist, onFocusChange: _onFocus),
                        ],
                      )),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(AppShape.radiusMd)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.success)),
                            const SizedBox(width: AppSpacing.md),
                            AppText('Playing from ${sourceParts.join(' · ')}', color: AppColors.ink2),
                          ],
                        ),
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
