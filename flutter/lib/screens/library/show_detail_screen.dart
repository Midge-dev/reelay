import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../focus/screen_memory.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/filter_chip.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watchlist_button.dart';
import 'movie_detail_sections.dart';

// Screen 04: content from 80 du down, 48 du from the rail, 80 du from the
// right edge; 30 du between hero, season chips and episodes; hero column
// 820 du wide beside a 220x330 poster 44 du away; blocks 14 du apart.
const _contentTop = 80.0;
const _contentRight = 80.0;
const _sectionGap = 30.0;
const _heroColumnMax = 820.0;
const _heroBlockGap = 14.0;
const _posterGap = 44.0;
const _synopsisMax = 720.0;
const _bottomFadeHeight = 600.0;
const _posterWidth = 220.0;
const _posterHeight = 330.0;
const _episodeThumbWidth = 220.0;
const _episodeThumbHeight = 124.0;
const _episodeGap = 12.0;
const _episodeSummaryMax = 900.0;

/// Ports screen 04 of the Nocturne handoff — "seasons are a chip row, not a
/// separate screen" — one fewer back-press between the show and an episode.
/// The episode list is the focus target on arrival, landing on the next
/// unwatched episode, not the hero's Play button. Replaces the old
/// MovieDetailScreen(isShow: true) + ShowSeasonsScreen + ShowEpisodesScreen
/// chain entirely.
class ShowDetailScreen extends StatefulWidget {
  final PlexServer server;
  final PlexLibraryItem show;
  final VoidCallback onBack;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onWatchTogether;
  final ValueChanged<PlexEpisode> onSelectEpisode;
  final bool Function(String?) isOnWatchlist;
  final ValueChanged<String?> onToggleWatchlist;
  final Future<PlexOnDeckItem?> Function() resolveNextEpisode;
  final Future<PlexMovieDetail?> Function() loadDetail;
  final Future<List<PlexSeason>> Function() loadSeasons;
  final Future<List<PlexEpisode>> Function(String seasonRatingKey) loadEpisodes;

  const ShowDetailScreen({
    super.key,
    required this.server,
    required this.show,
    required this.onBack,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onSelectEpisode,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.resolveNextEpisode,
    required this.loadDetail,
    required this.loadSeasons,
    required this.loadEpisodes,
  });

  @override
  State<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends State<ShowDetailScreen> {
  final _playFocus = FocusNode(debugLabel: 'show-detail-play');
  final _scrollController = ScrollController();

  PlexOnDeckItem? _nextEpisode;
  PlexMovieDetail? _detail;
  List<PlexSeason> _seasons = const [];
  PlexSeason? _selectedSeason;
  List<PlexEpisode> _episodes = const [];
  bool _episodesLoading = true;

  // Set once, from the initial load only — landing on the next unwatched
  // episode is an arrival behavior. Switching seasons afterward via the
  // chip row relies on ordinary directional focus traversal instead of
  // forcing focus back down into the list.
  String? _initialFocusEpisodeKey;
  FocusNode? _initialFocusNode;

  @override
  void initState() {
    super.initState();
    // Coming back from an episode: the same season, episodes and focused
    // row at once, then a quiet refresh that keeps that season.
    final kept = ScreenMemory.read<_ShowLoaded>(context, 'show.loaded');
    if (kept != null) {
      _nextEpisode = kept.nextEpisode;
      _detail = kept.detail;
      _seasons = kept.seasons;
      _selectedSeason = kept.selectedSeason;
      _episodes = kept.episodes;
      _episodesLoading = false;
      _initialFocusEpisodeKey = kept.initialFocusEpisodeKey;
    }
    _load(keepSeason: kept != null);
  }

  void _remember() => ScreenMemory.write(
    context,
    'show.loaded',
    _ShowLoaded(
      nextEpisode: _nextEpisode,
      detail: _detail,
      seasons: _seasons,
      selectedSeason: _selectedSeason,
      episodes: _episodes,
      initialFocusEpisodeKey: _initialFocusEpisodeKey,
    ),
  );

  @override
  void didUpdateWidget(covariant ShowDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.show.ratingKey != widget.show.ratingKey) {
      _initialFocusNode?.dispose();
      _initialFocusNode = null;
      setState(() {
        _nextEpisode = null;
        _detail = null;
        _seasons = const [];
        _selectedSeason = null;
        _episodes = const [];
        _episodesLoading = true;
        _initialFocusEpisodeKey = null;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _playFocus.dispose();
    _initialFocusNode?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepSeason = false}) async {
    final results = await Future.wait([
      widget.resolveNextEpisode(),
      widget.loadDetail(),
      widget.loadSeasons(),
    ]);
    if (!mounted) return;
    final next = results[0] as PlexOnDeckItem?;
    final detail = results[1] as PlexMovieDetail?;
    final seasons = results[2] as List<PlexSeason>;
    final kept = keepSeason
        ? seasons.firstWhereOrNull(
            (s) => s.ratingKey == _selectedSeason?.ratingKey,
          )
        : null;
    final target = kept ?? _pickInitialSeason(seasons, next);

    setState(() {
      _nextEpisode = next;
      _detail = detail;
      _seasons = seasons;
      _selectedSeason = target;
    });

    if (target == null) {
      setState(() => _episodesLoading = false);
      return;
    }
    final episodes = await widget.loadEpisodes(target.ratingKey);
    if (!mounted) return;

    final focusKey = _nextUpIn(episodes, next)?.ratingKey;
    // Landing on the next episode is for arriving, not for coming back.
    if (focusKey != null && kept == null) {
      _initialFocusNode = FocusNode(
        debugLabel: 'show-detail-episode-$focusKey',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initialFocusNode?.requestFocus();
      });
    }

    setState(() {
      _episodes = episodes;
      _episodesLoading = false;
      _initialFocusEpisodeKey = focusKey;
    });
  }

  /// Screen 04 lands on "the next unwatched episode": one already in
  /// progress, else Plex's own on-deck pick, else the first never-watched
  /// one, else the first.
  PlexEpisode? _nextUpIn(List<PlexEpisode> episodes, PlexOnDeckItem? onDeck) {
    if (episodes.isEmpty) return null;
    for (final e in episodes) {
      if ((e.viewOffset ?? 0) > 0) return e;
    }
    for (final e in episodes) {
      if (e.ratingKey == onDeck?.ratingKey) return e;
    }
    for (final e in episodes) {
      if ((e.viewCount ?? 0) == 0) return e;
    }
    return episodes.first;
  }

  PlexSeason? _pickInitialSeason(
    List<PlexSeason> seasons,
    PlexOnDeckItem? next,
  ) {
    if (seasons.isEmpty) return null;
    if (next?.parentIndex != null) {
      for (final season in seasons) {
        if (season.index == next!.parentIndex) return season;
      }
    }
    final numbered = seasons.where((s) => (s.index ?? 0) > 0).toList()
      ..sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0));
    return numbered.isNotEmpty ? numbered.first : seasons.first;
  }

  Future<void> _onSelectSeason(PlexSeason season) async {
    if (season.ratingKey == _selectedSeason?.ratingKey) return;
    setState(() {
      _selectedSeason = season;
      _episodesLoading = true;
      _episodes = const [];
    });
    final episodes = await widget.loadEpisodes(season.ratingKey);
    if (!mounted) return;
    setState(() {
      _episodes = episodes;
      _episodesLoading = false;
    });
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
    _remember();
    final detail = _detail;
    // The episode Play targets: the one focus lands on (in progress or
    // next unwatched), falling back to Plex's on-deck pick before episodes
    // load.
    final nextUp = _episodes
        .where((e) => e.ratingKey == _initialFocusEpisodeKey)
        .firstOrNull;
    final playTarget = nextUp?.ratingKey ?? _nextEpisode?.ratingKey;
    final seasonIndex =
        nextUp?.parentIndex ??
        _selectedSeason?.index ??
        _nextEpisode?.parentIndex;
    final episodeIndex = nextUp?.index ?? _nextEpisode?.index;
    final resuming = (nextUp?.viewOffset ?? 0) > 0;
    final playLabel = [
      resuming ? 'Resume' : 'Play',
      if (seasonIndex != null && episodeIndex != null)
        'S$seasonIndex E$episodeIndex',
    ].join(' ');
    final guid = detail?.guid ?? widget.show.guid;

    final sections = <Widget>[
      _ShowHero(
        server: widget.server,
        show: widget.show,
        year: widget.show.year ?? detail?.year,
        summary: detail?.summary ?? widget.show.summary,
        seasonCount: _seasons.length,
        playLabel: playLabel,
        playFocus: _playFocus,
        onPlay: playTarget != null ? () => widget.onPlay(playTarget) : null,
        onWatchTogether: playTarget != null
            ? () => widget.onWatchTogether(playTarget)
            : null,
        isOnWatchlist: widget.isOnWatchlist(guid),
        onToggleWatchlist: () => widget.onToggleWatchlist(guid),
        onActionButtonFocused: _scrollToTop,
      ),
      if (_seasons.isNotEmpty)
        _SeasonChipsRow(
          seasons: _seasons,
          selected: _selectedSeason,
          onSelect: _onSelectSeason,
        ),
      if (!_episodesLoading)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, episode) in _episodes.indexed) ...[
              if (i > 0) SizedBox(height: _episodeGap.du(context)),
              RememberFocus(
                key: ValueKey(episode.ratingKey),
                id: 'episode:${episode.ratingKey}',
                child: _EpisodeRow(
                  server: widget.server,
                  episode: episode,
                  focusNode: episode.ratingKey == _initialFocusEpisodeKey
                      ? _initialFocusNode
                      : null,
                  onClick: () => widget.onSelectEpisode(episode),
                ),
              ),
            ],
          ],
        ),
    ];

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The show's backdrop sits behind the whole page (screen 04),
            // under scrim.edge and a bottom fade into the ground, so the
            // episode list reads on the ground rather than on the art.
            Artwork(
              imageUrl: PlexImageUrl.of(
                widget.server,
                widget.show.art ?? widget.show.thumb,
              ),
            ),
            DecoratedBox(decoration: BoxDecoration(gradient: AppScrims.edge)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _bottomFadeHeight.du(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppGradients.linear(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0),
                      AppColors.background,
                    ],
                    stops: const [0, 0.55],
                  ),
                ),
              ),
            ),
            ListView.separated(
              key: const PageStorageKey('show-detail'),
              controller: _scrollController,
              // Focused rows scale 1.03 — keep them clear of the edges.
              clipBehavior: Clip.none,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.safeX.du(context),
                _contentTop.du(context),
                _contentRight.du(context),
                AppSpacing.safeY.du(context),
              ),
              itemCount: sections.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: _sectionGap.du(context)),
              itemBuilder: (context, index) => sections[index],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowHero extends StatelessWidget {
  final PlexServer server;
  final PlexLibraryItem show;
  final String? summary;

  /// First aired — the last chip on the meta line.
  final int? year;
  final int seasonCount;
  final String playLabel;
  final FocusNode playFocus;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchTogether;
  final bool isOnWatchlist;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onActionButtonFocused;

  const _ShowHero({
    required this.server,
    required this.show,
    this.year,
    this.summary,
    required this.seasonCount,
    required this.playLabel,
    required this.playFocus,
    this.onPlay,
    this.onWatchTogether,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.onActionButtonFocused,
  });

  void _onFocus(bool focused) {
    if (focused) onActionButtonFocused();
  }

  // Nothing sits above the action row — see movie_detail_screen.dart.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: _heroBlockGap.du(context));
    final episodes = show.leafCount;
    final meta = <String>[
      [
        if (seasonCount > 0)
          '$seasonCount season${seasonCount == 1 ? '' : 's'}',
        if (episodes != null) '$episodes episode${episodes == 1 ? '' : 's'}',
      ].join(' · '),
      if (show.genres.isNotEmpty) show.genres.first.tag,
    ].where((p) => p.isNotEmpty).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _heroColumnMax.du(context)),
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
                      AppText(
                        'SERIES · PLEX · ${server.name.toUpperCase()}',
                        style: AppTypography.micro,
                      ),
                    ],
                  ),
                  gap,
                  AppText(
                    show.title,
                    style: AppTypography.display,
                    color: AppColors.inkOnArt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  gap,
                  MetaRow(
                    parts: meta,
                    chips: [?show.contentRating, ?year?.toString()],
                  ),
                  if (summary != null && summary!.trim().isNotEmpty) ...[
                    gap,
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _synopsisMax.du(context),
                      ),
                      child: AppText(
                        summary!,
                        style: AppTypography.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  SizedBox(height: (_heroBlockGap + AppSpacing.sm).du(context)),
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: _trapUp,
                    child: Wrap(
                      spacing: _heroBlockGap.du(context),
                      runSpacing: _heroBlockGap.du(context),
                      children: [
                        RememberFocus(
                          id: 'play',
                          child: AppOutlinedButton(
                            onClick: onPlay ?? () {},
                            enabled: onPlay != null,
                            focusNode: playFocus,
                            onFocusChange: _onFocus,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  PhosphorIconsRegular.play,
                                  size: 22,
                                ),
                                SizedBox(width: AppSpacing.md.du(context)),
                                AppText(
                                  playLabel,
                                  style: AppTypography.label,
                                  color: null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        RememberFocus(
                          id: 'watch-together',
                          child: AppOutlinedButton(
                            onClick: onWatchTogether ?? () {},
                            enabled: onWatchTogether != null,
                            onFocusChange: _onFocus,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  PhosphorIconsRegular.usersThree,
                                  size: 22,
                                ),
                                SizedBox(width: AppSpacing.md.du(context)),
                                AppText(
                                  'Watch Together',
                                  style: AppTypography.label,
                                  color: null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        RememberFocus(
                          id: 'watchlist',
                          child: WatchlistButton(
                            isOnWatchlist: isOnWatchlist,
                            onClick: onToggleWatchlist,
                            onFocusChange: _onFocus,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: _posterGap.du(context)),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
          child: Container(
            width: _posterWidth.du(context),
            height: _posterHeight.du(context),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppShape.radiusMd.du(context),
              ),
              border: Border.all(
                color: AppColors.lineStrong,
                width: 1.du(context),
              ),
            ),
            child: Artwork(imageUrl: PlexImageUrl.of(server, show.thumb)),
          ),
        ),
      ],
    );
  }
}

/// What the show page keeps in its ScreenMemory besides focus and scroll.
class _ShowLoaded {
  final PlexOnDeckItem? nextEpisode;
  final PlexMovieDetail? detail;
  final List<PlexSeason> seasons;
  final PlexSeason? selectedSeason;
  final List<PlexEpisode> episodes;
  final String? initialFocusEpisodeKey;

  const _ShowLoaded({
    required this.nextEpisode,
    required this.detail,
    required this.seasons,
    required this.selectedSeason,
    required this.episodes,
    required this.initialFocusEpisodeKey,
  });
}

class _SeasonChipsRow extends StatelessWidget {
  final List<PlexSeason> seasons;
  final PlexSeason? selected;
  final ValueChanged<PlexSeason> onSelect;

  const _SeasonChipsRow({
    required this.seasons,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Numbered seasons in order; Specials (index 0/null) trails, matching
    // the common streaming-client convention rather than sorting it first.
    final sorted = [...seasons]
      ..sort((a, b) {
        final aSpecial = (a.index ?? 0) <= 0;
        final bSpecial = (b.index ?? 0) <= 0;
        if (aSpecial != bSpecial) return aSpecial ? 1 : -1;
        return (a.index ?? 0).compareTo(b.index ?? 0);
      });

    return Wrap(
      spacing: AppSpacing.md.du(context),
      runSpacing: AppSpacing.md.du(context),
      children: [
        for (final season in sorted)
          RememberFocus(
            key: ValueKey(season.ratingKey),
            id: 'season:${season.ratingKey}',
            child: AppFilterChip(
              selected: season.ratingKey == selected?.ratingKey,
              onClick: () => onSelect(season),
              child: AppText(
                season.title,
                style: AppTypography.caption,
                color: null,
              ),
            ),
          ),
      ],
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  final PlexServer server;
  final PlexEpisode episode;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _EpisodeRow({
    required this.server,
    required this.episode,
    this.focusNode,
    required this.onClick,
  });

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

/// Screen 04's episode row: a 220x124 still (with a progress rule when
/// started), "EPISODE 4" plus time left, the title, a two-line synopsis,
/// and the runtime — plus the play glyph once focused, since that's what
/// Select does. Focus is the standard surface signal; the kicker steps to
/// accent300 and the lines step up an ink level with it.
class _EpisodeRowState extends State<_EpisodeRow> {
  late final FocusNode _focusNode =
      widget.focusNode ??
      FocusNode(debugLabel: 'episode-row-${widget.episode.ratingKey}');
  bool _focused = false;

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final duration = episode.duration ?? 0;
    final offset = episode.viewOffset ?? 0;
    final remaining = duration - offset;
    final hasProgress = offset > 0 && remaining > 0;
    final progress = duration > 0 ? (offset / duration).clamp(0.0, 1.0) : 0.0;

    return AppCard(
      onClick: widget.onClick,
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20.du(context),
          vertical: AppSpacing.lg.du(context),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(
                AppShape.radiusSm.du(context),
              ),
              child: SizedBox(
                width: _episodeThumbWidth.du(context),
                height: _episodeThumbHeight.du(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(
                      imageUrl: PlexImageUrl.of(widget.server, episode.thumb),
                    ),
                    if (hasProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: AppSpacing.xs.du(context),
                        child: ColoredBox(
                          color: AppColors.ink.withValues(alpha: 0.22),
                          child: FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: progress,
                            child: ColoredBox(
                              color: _focused
                                  ? AppColors.accent
                                  : AppColors.ink3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 22.du(context)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppText(
                        'EPISODE ${episode.index ?? '—'}',
                        style: AppTypography.caption,
                        color: _focused ? AppColors.accent300 : AppColors.ink3,
                      ),
                      if (hasProgress) ...[
                        SizedBox(width: 14.du(context)),
                        AppText(
                          formatMinutesLeft(remaining),
                          style: AppTypography.caption,
                          color: AppColors.ink2,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 5.du(context)),
                  AppText(
                    episode.title,
                    style: AppTypography.rowLabel.copyWith(
                      fontWeight: _focused ? FontWeight.w500 : FontWeight.w400,
                    ),
                    color: _focused ? AppColors.ink : AppColors.ink2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (episode.summary != null &&
                      episode.summary!.trim().isNotEmpty) ...[
                    SizedBox(height: 6.du(context)),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _episodeSummaryMax.du(context),
                      ),
                      child: AppText(
                        episode.summary!,
                        style: AppTypography.caption.copyWith(height: 1.5),
                        color: _focused ? AppColors.ink2 : AppColors.ink3,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 22.du(context)),
            AppText(
              formatRuntime(duration),
              style: AppTypography.caption,
              color: AppColors.ink3,
            ),
            if (_focused) ...[
              SizedBox(width: 14.du(context)),
              const AppIcon(PhosphorIconsFill.play, size: 26),
            ],
          ],
        ),
      ),
    );
  }
}
