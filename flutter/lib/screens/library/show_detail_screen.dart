import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/filter_chip.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watch_together_icon.dart';
import '../common/watchlist_button.dart';

const _heroHeight = 620.0;
const _posterWidth = 220.0;
const _posterHeight = 330.0;
const _episodeThumbWidth = 220.0;
const _episodeThumbHeight = 124.0;

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
    _load();
  }

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

  Future<void> _load() async {
    final results = await Future.wait([
      widget.resolveNextEpisode(),
      widget.loadDetail(),
      widget.loadSeasons(),
    ]);
    if (!mounted) return;
    final next = results[0] as PlexOnDeckItem?;
    final detail = results[1] as PlexMovieDetail?;
    final seasons = results[2] as List<PlexSeason>;
    final target = _pickInitialSeason(seasons, next);

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

    final wanted = next?.ratingKey;
    final hasWanted =
        wanted != null && episodes.any((e) => e.ratingKey == wanted);
    final focusKey = hasWanted
        ? wanted
        : (episodes.isNotEmpty ? episodes.first.ratingKey : null);
    if (focusKey != null) {
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
    final detail = _detail;
    final playTarget = _nextEpisode?.ratingKey;
    final playLabel = _nextEpisode != null
        ? 'Play S${_nextEpisode!.parentIndex}E${_nextEpisode!.index}'
        : 'Play';
    final guid = detail?.guid ?? widget.show.guid;

    final sections = <Widget>[
      _ShowHero(
        server: widget.server,
        show: widget.show,
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
    ];

    if (_seasons.isNotEmpty) {
      sections.add(
        _SeasonChipsRow(
          seasons: _seasons,
          selected: _selectedSeason,
          onSelect: _onSelectSeason,
        ),
      );
    }

    if (!_episodesLoading) {
      for (final episode in _episodes) {
        sections.add(
          _EpisodeRow(
            key: ValueKey(episode.ratingKey),
            server: widget.server,
            episode: episode,
            isNextUp: episode.ratingKey == _nextEpisode?.ratingKey,
            focusNode: episode.ratingKey == _initialFocusEpisodeKey
                ? _initialFocusNode
                : null,
            onClick: () => widget.onSelectEpisode(episode),
          ),
        );
      }
    }
    sections.add(const SizedBox(height: 48));

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: ListView.separated(
          controller: _scrollController,
          itemCount: sections.length,
          separatorBuilder: (context, index) => const SizedBox(height: 20),
          itemBuilder: (context, index) => sections[index],
        ),
      ),
    );
  }
}

class _ShowHero extends StatelessWidget {
  final PlexServer server;
  final PlexLibraryItem show;
  final String? summary;
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

  // Nothing sits above the action button row (it's the top of the hero) —
  // see the matching comment in movie_detail_screen.dart.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (show.year != null) '${show.year}',
      if (seasonCount > 0) '$seasonCount season${seasonCount == 1 ? '' : 's'}',
      if (show.leafCount != null)
        '${show.leafCount} episode${show.leafCount == 1 ? '' : 's'}',
      if (show.genres.isNotEmpty) show.genres.first.tag,
      if (show.contentRating != null) show.contentRating!,
    ];

    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            imageUrl: PlexImageUrl.of(server, show.art ?? show.thumb),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxxl,
              AppSpacing.xxl,
              AppSpacing.xxxl,
              AppSpacing.xl,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 2,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          AppText('SHOW', style: AppTypography.micro),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: AppText(
                          show.title,
                          style: AppTypography.display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AppText(metaParts.join(' · '), color: AppColors.ink2),
                      ],
                      if (summary != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 780),
                          child: AppText(
                            summary!,
                            style: AppTypography.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      Focus(
                        canRequestFocus: false,
                        onKeyEvent: _trapUp,
                        child: Wrap(
                          // Wrap, not Row — a long "Play S3E12" label plus
                          // Watch Together and the watchlist button can be
                          // wider than the column allows. See the matching
                          // comment in movie_detail_screen.dart.
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.md,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppButton(
                              onClick: onPlay ?? () {},
                              focusNode: playFocus,
                              onFocusChange: _onFocus,
                              child: AppText(playLabel),
                            ),
                            AppOutlinedButton(
                              onClick: onWatchTogether ?? () {},
                              onFocusChange: _onFocus,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const WatchTogetherIcon(),
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      left: AppSpacing.sm,
                                    ),
                                    child: AppText('Watch Together'),
                                  ),
                                ],
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
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xxl),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppShape.radiusMd),
                  child: Container(
                    width: _posterWidth,
                    height: _posterHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: Artwork(
                      imageUrl: PlexImageUrl.of(server, show.thumb),
                    ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final season in sorted)
            AppFilterChip(
              key: ValueKey(season.ratingKey),
              selected: season.ratingKey == selected?.ratingKey,
              onClick: () => onSelect(season),
              child: AppText(season.title),
            ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  final PlexServer server;
  final PlexEpisode episode;
  final bool isNextUp;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _EpisodeRow({
    super.key,
    required this.server,
    required this.episode,
    required this.isNextUp,
    this.focusNode,
    required this.onClick,
  });

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

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
    final remaining = duration - (episode.viewOffset ?? 0);
    final hasProgress = (episode.viewOffset ?? 0) > 0 && remaining > 0;
    final progress = duration > 0
        ? ((episode.viewOffset ?? 0) / duration).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: AppCard(
        onClick: widget.onClick,
        focusNode: _focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShape.radiusSm),
                child: SizedBox(
                  width: _episodeThumbWidth,
                  height: _episodeThumbHeight,
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
                          child: Container(
                            height: 4,
                            color: AppColors.ink.withValues(alpha: 0.22),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: ColoredBox(color: AppColors.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
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
                        ),
                        if (hasProgress) ...[
                          const SizedBox(width: AppSpacing.md),
                          AppText(
                            formatMinutesLeft(remaining),
                            style: AppTypography.caption,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      episode.title,
                      style: _focused
                          ? AppTypography.label.copyWith(
                              fontWeight: FontWeight.w500,
                            )
                          : AppTypography.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episode.summary != null) ...[
                      const SizedBox(height: 4),
                      AppText(
                        episode.summary!,
                        style: AppTypography.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    formatRuntime(duration),
                    style: AppTypography.caption,
                  ),
                  if (widget.isNextUp) ...[
                    const SizedBox(width: AppSpacing.md),
                    const AppIcon(PhosphorIconsFill.play, size: 26),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
