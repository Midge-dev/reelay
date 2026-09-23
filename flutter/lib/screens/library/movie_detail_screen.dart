import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/time_format.dart';
import '../common/watchlist_button.dart';
import 'media_facts.dart';
import 'movie_detail_sections.dart';
import 'poster_card.dart';
import 'source_picker_dialog.dart';

// Screen 03: content 96 du from the top, 48 from the rail, 80 from the
// right; poster 280x420 48 du from a facts column capped at 960; blocks
// 16 apart; a 540 du bottom fade. Screen 03b: a 112 du compact header once
// the hero has scrolled away.
const _contentTop = 96.0;
const _contentRight = 80.0;
const _posterWidth = 280.0;
const _posterHeight = 420.0;
const _posterGap = 48.0;
const _factsMax = 960.0;
const _blockGap = 16.0;
const _synopsisMax = 780.0;
const _bottomFadeHeight = 540.0;
const _progressBarWidth = 380.0;
const _compactHeaderHeight = 112.0;
const _moreLikeThisMax = 20;

SurfaceBorder get _restartButtonBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.lineStrong),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// Screen 03 (and 03b, scrolled). Poster left, facts right, actions on
/// one line, the media facts stated plainly. Below the hero the page
/// holds exactly two rows — Cast & crew, and More like this — because "a
/// detail page that shrinks its rows to fit is carrying too much". Once
/// the hero scrolls away a compact header keeps the title and the resume
/// point in view.
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
    required this.onSelectRelated,
    required this.onSelectPerson,
    required this.onSwitchSource,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final _playFocus = FocusNode(debugLabel: 'movie-detail-play');
  final _scrollController = ScrollController();
  final _heroKey = GlobalKey();

  PlexMovieDetail? _detail;
  List<PlexOnDeckItem> _moreLikeThis = const [];
  bool _showingSourcePicker = false;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
        _moreLikeThis = const [];
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _playFocus.requestFocus(),
      );
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _playFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final heroHeight =
        (_heroKey.currentContext?.findRenderObject() as RenderBox?)
            ?.size
            .height;
    if (heroHeight == null) return;
    // The compact header arrives once the actions have gone under it.
    final compact = _scrollController.offset > heroHeight * 0.55;
    if (compact != _compact) setState(() => _compact = compact);
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.loadDetail(),
      widget.loadRelatedHubs(),
    ]);
    if (!mounted) return;
    final hubs = results[1] as List<PlexHub>;
    setState(() {
      _detail = results[0] as PlexMovieDetail?;
      _moreLikeThis = _mergeRelated(hubs);
    });
  }

  /// One "More like this" row out of Plex's related hubs — similar titles
  /// first, then collections and the rest — deduplicated, without this
  /// title, drawn only from the server's own libraries.
  List<PlexOnDeckItem> _mergeRelated(List<PlexHub> hubs) {
    int rank(PlexHub h) {
      final id = '${h.hubIdentifier ?? ''} ${h.title}'.toLowerCase();
      if (id.contains('similar') || id.contains('like this')) return 0;
      if (id.contains('collection')) return 1;
      return 2;
    }

    final ordered = [...hubs]..sort((a, b) => rank(a).compareTo(rank(b)));
    final seen = <String>{widget.movie.ratingKey};
    return [
      for (final hub in ordered)
        for (final item in hub.items)
          if (seen.add(item.ratingKey)) item,
    ].take(_moreLikeThisMax).toList();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients || _scrollController.offset == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: AppMotion.rowScroll,
          curve: AppMotion.enter,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final duration = detail?.duration;
    final viewOffset = detail?.viewOffset ?? 0;
    final hasResume = viewOffset > 0;
    final remaining = (duration ?? 0) - viewOffset;
    final media = detail?.media.isNotEmpty == true
        ? MediaFacts(detail!.media.first)
        : null;
    final meta = [
      if (widget.movie.year != null) '${widget.movie.year}',
      if (duration != null) formatRuntime(duration),
    ];

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => ListView(
                controller: _scrollController,
                clipBehavior: Clip.none,
                padding: EdgeInsets.only(bottom: AppSpacing.safeY.du(context)),
                children: [
                  _HeroViewport(
                    key: _heroKey,
                    minHeight: constraints.maxHeight,
                    backdrop: PlexImageUrl.of(
                      widget.server,
                      widget.movie.art ?? widget.movie.thumb,
                    ),
                    hero: _Hero(
                      server: widget.server,
                      movie: widget.movie,
                      detail: detail,
                      media: media,
                      hasResume: hasResume,
                      remainingMs: remaining,
                      progress: (duration ?? 0) > 0
                          ? (viewOffset / duration!).clamp(0.0, 1.0)
                          : 0.0,
                      playFocus: _playFocus,
                      onPlay: () => widget.onPlay(widget.movie.ratingKey),
                      onWatchTogether: () =>
                          widget.onWatchTogether(widget.movie.ratingKey),
                      onRestartSolo: () =>
                          widget.onRestartSolo(widget.movie.ratingKey),
                      isOnWatchlist: widget.isOnWatchlist(
                        detail?.guid ?? widget.movie.guid,
                      ),
                      onToggleWatchlist: () => widget.onToggleWatchlist(
                        detail?.guid ?? widget.movie.guid,
                      ),
                      onActionFocused: _scrollToTop,
                      copyCount: widget.work.copies.length,
                      onOpenSourcePicker: widget.work.copies.length > 1
                          ? () => setState(() => _showingSourcePicker = true)
                          : null,
                    ),
                    footer: detail == null
                        ? null
                        : CastCrewRow(
                            server: widget.server,
                            cast: detail.roles,
                            directors: detail.directors,
                            writers: detail.writers,
                            onSelectPerson: widget.onSelectPerson,
                          ),
                  ),
                  if (_moreLikeThis.isNotEmpty)
                    _MoreLikeThis(
                      items: _moreLikeThis,
                      serverName: widget.server.name,
                      server: widget.server,
                      onSelect: widget.onSelectRelated,
                    ),
                ],
              ),
            ),
            // 03b's compact header: title, facts and the resume point stay
            // in view while the rows below are browsed. A reminder, not a
            // focus target — Up from the rows still returns to the hero's
            // own actions (and scrolls it back).
            IgnorePointer(
              child: ExcludeFocus(
                child: AnimatedSwitcher(
                  duration: AppMotion.overlayIn,
                  reverseDuration: AppMotion.overlayOut,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  child: _compact
                      ? _CompactHeader(
                          server: widget.server,
                          movie: widget.movie,
                          meta: [
                            ...meta,
                            'playing from ${widget.server.name}',
                          ].join(' · '),
                          action: hasResume
                              ? 'Resume · ${formatMinutesLeft(remaining)}'
                              : 'Play',
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            if (_showingSourcePicker)
              SourcePickerDialog(
                title: widget.movie.title,
                work: widget.work,
                activeCopy: widget.work.copies.firstWhere(
                  (c) =>
                      c.server.machineIdentifier ==
                      widget.server.machineIdentifier,
                  orElse: () => widget.work.primary,
                ),
                onSelect: widget.onSwitchSource,
                onClose: () => setState(() => _showingSourcePicker = false),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first screen of the page: the backdrop and its scrims behind the
/// hero, with Cast & crew pinned to its foot — at least one viewport tall,
/// taller only when a large UI size needs it.
class _HeroViewport extends StatelessWidget {
  final double minHeight;
  final String? backdrop;
  final Widget hero;
  final Widget? footer;

  const _HeroViewport({
    super.key,
    required this.minHeight,
    this.backdrop,
    required this.hero,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: Artwork(imageUrl: backdrop)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppScrims.edge),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _bottomFadeHeight.du(context),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background,
                  ],
                  stops: const [0, 0.58],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.safeX.du(context),
                  _contentTop.du(context),
                  _contentRight.du(context),
                  0,
                ),
                child: hero,
              ),
              if (footer != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: AppSpacing.xxl.du(context),
                    bottom: AppSpacing.safeY.du(context),
                  ),
                  child: footer,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final PlexServer server;
  final PlexLibraryItem movie;
  final PlexMovieDetail? detail;
  final MediaFacts? media;
  final bool hasResume;
  final int remainingMs;
  final double progress;
  final FocusNode playFocus;
  final VoidCallback onPlay;
  final VoidCallback onWatchTogether;
  final VoidCallback onRestartSolo;
  final bool isOnWatchlist;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onActionFocused;
  final int copyCount;
  final VoidCallback? onOpenSourcePicker;

  const _Hero({
    required this.server,
    required this.movie,
    required this.detail,
    required this.media,
    required this.hasResume,
    required this.remainingMs,
    required this.progress,
    required this.playFocus,
    required this.onPlay,
    required this.onWatchTogether,
    required this.onRestartSolo,
    required this.isOnWatchlist,
    required this.onToggleWatchlist,
    required this.onActionFocused,
    required this.copyCount,
    this.onOpenSourcePicker,
  });

  void _onFocus(bool focused) {
    if (focused) onActionFocused();
  }

  // Nothing sits above the action row — without this Up escapes to the
  // nearest thing geometrically above, which is nothing on this page.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: _blockGap.du(context));
    final duration = detail?.duration;
    final summary = detail?.summary ?? movie.summary;
    final rating = detail?.contentRating ?? movie.contentRating;
    final meta = [
      if (movie.year != null) '${movie.year}',
      if (duration != null) formatRuntime(duration),
      if (movie.genres.isNotEmpty) movie.genres.first.tag,
    ];
    final chips = [?rating, ?media?.picture, ?media?.audio];
    final directors = detail?.directors.map((p) => p.tag).take(2).join(', ');
    final facts = <(String, String)>[
      if (directors != null && directors.isNotEmpty) ('Director', directors),
      if (detail?.studio != null) ('Studio', detail!.studio!),
      if (media?.subtitles != null) ('Subtitles', media!.subtitles!),
      if (media?.file != null) ('File', media!.file!),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            child: Artwork(imageUrl: PlexImageUrl.of(server, movie.thumb)),
          ),
        ),
        SizedBox(width: _posterGap.du(context)),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _factsMax.du(context)),
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
                  gap,
                  AppText(
                    movie.title,
                    style: AppTypography.display,
                    color: AppColors.inkOnArt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  gap,
                  MetaRow(parts: meta, chips: chips),
                  if (hasResume && remainingMs > 0) ...[
                    gap,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2.du(context)),
                          child: SizedBox(
                            width: _progressBarWidth.du(context),
                            height: AppSpacing.xs.du(context),
                            child: ColoredBox(
                              color: AppColors.ink.withValues(alpha: 0.22),
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: progress,
                                child: ColoredBox(color: AppColors.accent),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.lg.du(context)),
                        AppText(
                          formatMinutesLeft(remainingMs),
                          style: AppTypography.caption,
                          color: AppColors.ink2,
                        ),
                      ],
                    ),
                  ],
                  if (summary != null && summary.trim().isNotEmpty) ...[
                    gap,
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _synopsisMax.du(context),
                      ),
                      child: AppText(
                        summary,
                        style: AppTypography.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  SizedBox(height: (_blockGap + 10).du(context)),
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: _trapUp,
                    child: Wrap(
                      spacing: AppSpacing.lg.du(context),
                      runSpacing: AppSpacing.lg.du(context),
                      children: [
                        AppButton(
                          onClick: onPlay,
                          focusNode: playFocus,
                          onFocusChange: _onFocus,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon(PhosphorIconsFill.play, size: 22),
                              SizedBox(width: AppSpacing.md.du(context)),
                              AppText(
                                hasResume ? 'Resume' : 'Play',
                                style: AppTypography.label,
                                color: null,
                              ),
                            ],
                          ),
                        ),
                        AppOutlinedButton(
                          onClick: onWatchTogether,
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
                        if (hasResume)
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
                  SizedBox(height: _blockGap.du(context)),
                  _SourceChip(
                    serverName: server.name,
                    facts: [
                      ?media?.picture,
                      if (media?.media.videoCodec != null)
                        media!.media.videoCodec!.toUpperCase(),
                    ],
                    copyCount: copyCount,
                    onClick: onOpenSourcePicker,
                  ),
                  if (facts.isNotEmpty) ...[
                    SizedBox(height: 14.du(context)),
                    Wrap(
                      spacing: 56.du(context),
                      runSpacing: AppSpacing.lg.du(context),
                      children: [
                        for (final (label, value) in facts)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppText(
                                label,
                                style: AppTypography.caption,
                                color: AppColors.ink,
                              ),
                              SizedBox(height: 5.du(context)),
                              AppText(value, style: AppTypography.caption),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

SurfaceColors get _sourceChipColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _sourceChipBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// "● Playing from Attic · 4K HDR │ 3 copies ›" — a fact when there is one
/// copy, the way into the source picker (03d) when folding found more.
class _SourceChip extends StatelessWidget {
  final String serverName;
  final List<String> facts;
  final int copyCount;
  final VoidCallback? onClick;

  const _SourceChip({
    required this.serverName,
    required this.facts,
    required this.copyCount,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 56.du(context)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.du(context)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSpacing.sm.du(context),
              height: AppSpacing.sm.du(context),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
              ),
            ),
            SizedBox(width: 18.du(context)),
            AppText(
              'Playing from ',
              style: AppTypography.caption,
              color: AppColors.ink2,
            ),
            AppText(
              serverName,
              style: AppTypography.caption,
              color: AppColors.ink,
            ),
            if (facts.isNotEmpty)
              AppText(
                ' · ${facts.join(' · ')}',
                style: AppTypography.caption,
                color: AppColors.ink2,
              ),
            if (onClick != null) ...[
              SizedBox(width: 18.du(context)),
              Container(
                width: 1.du(context),
                height: 26.du(context),
                color: AppColors.line,
              ),
              SizedBox(width: 18.du(context)),
              AppText('$copyCount copies', style: AppTypography.caption),
              SizedBox(width: AppSpacing.sm.du(context)),
              AppIcon(
                PhosphorIconsRegular.caretRight,
                size: 18,
                tint: AppColors.ink4,
              ),
            ],
          ],
        ),
      ),
    );
    final radius = BorderRadius.circular(AppShape.radiusMd.du(context));
    if (onClick == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: AppColors.line,
            width: AppShape.borderWidth.du(context),
          ),
          borderRadius: radius,
        ),
        child: content,
      );
    }
    return AppCard(
      onClick: onClick!,
      colors: _sourceChipColors,
      border: _sourceChipBorder,
      child: content,
    );
  }
}

/// 03b's only other row: titles like this one, drawn from the server's
/// own libraries — full-size posters, as everywhere else.
class _MoreLikeThis extends StatelessWidget {
  final List<PlexOnDeckItem> items;
  final String serverName;
  final PlexServer server;
  final ValueChanged<PlexOnDeckItem> onSelect;

  const _MoreLikeThis({
    required this.items,
    required this.serverName,
    required this.server,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RowHeading(
          title: 'More like this',
          hint: 'Drawn from your libraries, not from a recommendation service',
        ),
        SizedBox(
          height: (AppSpacing.lg - AppSpacing.rowHeadroom / 2).du(context),
        ),
        SizedBox(
          height: (posterCardExtent + AppSpacing.rowHeadroom).du(context),
          child: EdgeFadeRow(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.safeX.du(context),
                vertical: (AppSpacing.rowHeadroom / 2).du(context),
              ),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  SizedBox(width: AppSpacing.xl.du(context)),
              itemBuilder: (context, index) {
                final item = items[index];
                return PosterCard(
                  key: ValueKey(item.ratingKey),
                  imageUrl: PlexImageUrl.of(server, item.thumb),
                  title: item.title,
                  subtitle: serverName,
                  onClick: () => onSelect(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactHeader extends StatelessWidget {
  final PlexServer server;
  final PlexLibraryItem movie;
  final String meta;
  final String action;

  const _CompactHeader({
    required this.server,
    required this.movie,
    required this.meta,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _compactHeaderHeight.du(context),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.safeX.du(context),
        0,
        _contentRight.du(context),
        0,
      ),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(
          bottom: BorderSide(color: AppColors.line, width: 1.du(context)),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5.du(context)),
            child: SizedBox(
              width: 44.du(context),
              height: 66.du(context),
              child: Artwork(imageUrl: PlexImageUrl.of(server, movie.thumb)),
            ),
          ),
          SizedBox(width: AppSpacing.xl.du(context)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  movie.title,
                  style: AppTypography.rowLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 3.du(context)),
                AppText(
                  meta,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            height: 48.du(context),
            padding: EdgeInsets.symmetric(horizontal: 22.du(context)),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.lineStrong,
                width: AppShape.borderWidth.du(context),
              ),
              borderRadius: BorderRadius.circular(
                AppShape.radiusSm.du(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(PhosphorIconsFill.play, size: 20, tint: AppColors.ink2),
                SizedBox(width: 10.du(context)),
                AppText(
                  action,
                  style: AppTypography.caption,
                  color: AppColors.ink2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
