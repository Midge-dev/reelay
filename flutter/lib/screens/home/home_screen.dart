import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../focus/screen_memory.dart';
import '../../focus/row_end_stop.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../library/poster_card.dart';
import 'home_hero.dart';
import 'home_posters.dart';
import 'watch_together_bar.dart';
import 'watch_together_row.dart' show MergedRoom;

const _watchTogetherFocusQuietMs = 1200;
const _watchTogetherScrollDurationMs = 1100;

/// The most complex screen in the app.
/// Cascading "which row gets initial focus" priority (the resume hero, else
/// the first non-empty row among Watch Together > Watchlist > Recently
/// Finished > Recently Added > Suggestions), a debounced
/// scroll-to-top for Watch Together once D-pad input goes quiet, and
/// checklist item #2 (removing a focused list item must reclaim focus
/// *within that row*) via [_ReclaimFocusOnRemoval] — the one checklist
/// item the flutter-reelay PoC left genuinely untested, now real.
class HomeScreen extends StatefulWidget {
  final List<ReachableServer> servers;
  final List<PlexResource> unreachableResources;
  final List<FoldedWork<PlexOnDeckItem>> onDeck;
  final List<FoldedWork<PlexLibraryItem>> recentlyAdded;
  final List<FoldedWork<PlexOnDeckItem>> recentActivity;
  final List<FoldedWork<PlexOnDeckItem>> suggestions;
  final List<PlexWatchlistItem> watchlist;
  final List<MergedRoom> liveRooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final Future<bool> Function(MergedRoom) onEndSession;
  final ValueChanged<MergedRoom> onSelectRoom;
  final VoidCallback onOpenRooms;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onResume;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onRemove;
  final ValueChanged<PlexWatchlistItem> onSelectWatchlistItem;
  final ValueChanged<PlexWatchlistItem> onRemoveFromWatchlist;
  final ValueChanged<FoldedWork<PlexLibraryItem>> onSelectRecentlyAdded;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onSelectRecentActivity;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onSelectSuggestion;
  final ValueChanged<Sourced<PlexOnDeckItem>>? onHeroWatchTogether;

  const HomeScreen({
    super.key,
    required this.servers,
    this.unreachableResources = const [],
    this.onDeck = const [],
    this.recentlyAdded = const [],
    this.recentActivity = const [],
    this.suggestions = const [],
    this.watchlist = const [],
    this.liveRooms = const [],
    this.myRoomId,
    this.hostedRoomIds = const {},
    required this.onEndSession,
    required this.onSelectRoom,
    required this.onOpenRooms,
    required this.onResume,
    required this.onRemove,
    required this.onSelectWatchlistItem,
    required this.onRemoveFromWatchlist,
    required this.onSelectRecentlyAdded,
    required this.onSelectRecentActivity,
    required this.onSelectSuggestion,
    this.onHeroWatchTogether,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _homeScrollController = ScrollController();

  final _watchTogetherRowFocus = FocusNode(
    debugLabel: 'home-watch-together-row',
  );
  final _watchlistRowFocus = FocusNode(debugLabel: 'home-watchlist-row');
  final _continueWatchingRowFocus = FocusNode(
    debugLabel: 'home-continue-watching-row',
  );

  int _lastInputAtMs = 0;
  bool _hasScrolledToTopForWatchTogether = false;

  int _prevLiveRoomsCount = 0;
  int _prevWatchlistCount = 0;
  int _prevOnDeckCount = 0;

  @override
  void initState() {
    super.initState();
    _prevLiveRoomsCount = widget.liveRooms.length;
    _prevWatchlistCount = widget.watchlist.length;
    _prevOnDeckCount = widget.onDeck.length;
    // Rooms already live at mount are covered by the default focus; only
    // rooms appearing later pull the page to the top. Otherwise coming
    // back to Home with a room live yanked it off the remembered card.
    _hasScrolledToTopForWatchTogether = widget.liveRooms.isNotEmpty;
    HardwareKeyboard.instance.addHandler(_recordInput);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reclaimFocusOnRemoval(
      widget.liveRooms.length,
      _prevLiveRoomsCount,
      _watchTogetherRowFocus,
    );
    _reclaimFocusOnRemoval(
      widget.watchlist.length,
      _prevWatchlistCount,
      _watchlistRowFocus,
    );
    _reclaimFocusOnRemoval(
      widget.onDeck.length,
      _prevOnDeckCount,
      _continueWatchingRowFocus,
    );
    _prevLiveRoomsCount = widget.liveRooms.length;
    _prevWatchlistCount = widget.watchlist.length;
    _prevOnDeckCount = widget.onDeck.length;

    if (widget.liveRooms.isNotEmpty && !_hasScrolledToTopForWatchTogether) {
      _hasScrolledToTopForWatchTogether = true;
      _scrollToTopWhenQuiet();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_recordInput);
    _homeScrollController.dispose();
    _watchTogetherRowFocus.dispose();
    _watchlistRowFocus.dispose();
    _continueWatchingRowFocus.dispose();
    super.dispose();
  }

  bool _recordInput(KeyEvent event) {
    _lastInputAtMs = DateTime.now().millisecondsSinceEpoch;
    return false; // never consume — this is passive notification only.
  }

  /// If a row shrank (an
  /// item was removed) and still has items left, reclaim focus onto the
  /// row's anchor so it doesn't fall through to wherever the platform's
  /// default disposal search sends it (checklist item #2).
  void _reclaimFocusOnRemoval(
    int newSize,
    int previousSize,
    FocusNode rowFocus,
  ) {
    final wasRemoved = newSize < previousSize;
    if (wasRemoved && newSize > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rowFocus.requestFocus();
      });
    }
  }

  Future<void> _scrollToTopWhenQuiet() async {
    while (true) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - _lastInputAtMs;
      if (elapsed >= _watchTogetherFocusQuietMs) break;
      await Future.delayed(
        Duration(milliseconds: _watchTogetherFocusQuietMs - elapsed),
      );
      if (!mounted) return;
    }
    if (!mounted || !_homeScrollController.hasClients) return;
    await _homeScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: _watchTogetherScrollDurationMs),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Screen 01: Home opens on the resume hero's Resume — "real data, the
    // top in-progress item" — whenever there is one. Otherwise the first
    // row that exists, top to bottom. Coming back to Home, the card that
    // was left focused gets it instead (ScreenMemory).
    final restoring = ScreenMemory.restoringOf(context);
    final continueWatchingGetsFocus = !restoring && widget.onDeck.isNotEmpty;
    final watchTogetherGetsFocus =
        !restoring && !continueWatchingGetsFocus && widget.liveRooms.isNotEmpty;
    final watchlistGetsFocus =
        !restoring &&
        !continueWatchingGetsFocus &&
        !watchTogetherGetsFocus &&
        widget.watchlist.isNotEmpty;
    final recentActivityGetsFocus =
        !restoring &&
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        widget.recentActivity.isNotEmpty;
    final recentlyAddedGetsFocus =
        !restoring &&
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        !recentActivityGetsFocus &&
        widget.recentlyAdded.isNotEmpty;
    final suggestionsGetsFocus =
        !restoring &&
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        !recentActivityGetsFocus &&
        !recentlyAddedGetsFocus &&
        widget.suggestions.isNotEmpty;

    final watchlistReversed = widget.watchlist.reversed.toList();
    // Which row sits directly under the hero (see _HomeRow.afterHero).
    final rowsFilled = [
      watchlistReversed.isNotEmpty,
      widget.recentActivity.isNotEmpty,
      widget.recentlyAdded.isNotEmpty,
      widget.suggestions.isNotEmpty,
    ];
    final firstRow = widget.onDeck.isEmpty ? -1 : rowsFilled.indexOf(true);

    final watchTogetherBar = widget.liveRooms.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.safeX.du(context),
            ),
            child: WatchTogetherBar(
              rooms: widget.liveRooms,
              myRoomId: widget.myRoomId,
              hostedRoomIds: widget.hostedRoomIds,
              onEndSession: widget.onEndSession,
              onSelectRoom: widget.onSelectRoom,
              onMoreRooms: widget.onOpenRooms,
              focusNode: _watchTogetherRowFocus,
              autofocus: watchTogetherGetsFocus,
            ),
          );

    return ColoredBox(
      color: AppColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          key: const PageStorageKey('home'),
          controller: _homeScrollController,
          padding: EdgeInsets.only(bottom: AppSpacing.safeY.du(context)),
          children: [
            if (widget.unreachableResources.isNotEmpty)
              _buildPartialOutageBanner(),
            if (widget.onDeck.isNotEmpty)
              _buildHeroViewport(
                constraints.maxHeight,
                continueWatchingGetsFocus,
                watchTogetherBar,
              )
            else if (watchTogetherBar != null)
              // First-run empty: no hero and no message (DESIGN.md) — home
              // opens on its rows, with the bar above them when a room is live.
              Padding(
                padding: EdgeInsets.only(top: AppSpacing.safeY.du(context)),
                child: watchTogetherBar,
              ),
            _HomeRow<PlexWatchlistItem>(
              title: 'Watchlist',
              items: watchlistReversed,
              afterHero: firstRow == 0,
              idOf: (entry) => entry.ratingKey,
              itemBuilder: (entry, index) => WatchlistPoster(
                key: ValueKey(entry.ratingKey),
                server: widget.servers.first.server,
                entry: entry,
                onClick: () => widget.onSelectWatchlistItem(entry),
                onRemove: () => widget.onRemoveFromWatchlist(entry),
                focusNode: index == 0 ? _watchlistRowFocus : null,
                autofocus: index == 0 && watchlistGetsFocus,
              ),
            ),
            _HomeRow<FoldedWork<PlexOnDeckItem>>(
              title: 'Recently Finished Watching',
              items: widget.recentActivity,
              afterHero: firstRow == 1,
              idOf: _workId,
              itemBuilder: (item, index) => PosterCard(
                key: ValueKey(
                  '${item.primary.server.machineIdentifier}:${item.primary.value.ratingKey}',
                ),
                imageUrl: PlexImageUrl.of(
                  item.primary.server,
                  item.primary.value.thumb,
                ),
                title: continueWatchingLabel(item.primary.value),
                onClick: () => widget.onSelectRecentActivity(item),
                autofocus: index == 0 && recentActivityGetsFocus,
              ),
            ),
            _HomeRow<FoldedWork<PlexLibraryItem>>(
              title: 'Recently Added',
              items: widget.recentlyAdded,
              afterHero: firstRow == 2,
              idOf: _workId,
              itemBuilder: (item, index) => PosterCard(
                key: ValueKey(
                  '${item.primary.server.machineIdentifier}:${item.primary.value.ratingKey}',
                ),
                imageUrl: PlexImageUrl.of(
                  item.primary.server,
                  item.primary.value.thumb,
                ),
                title: recentlyAddedLabel(item.primary.value),
                onClick: () => widget.onSelectRecentlyAdded(item),
                autofocus: index == 0 && recentlyAddedGetsFocus,
              ),
            ),
            _HomeRow<FoldedWork<PlexOnDeckItem>>(
              title: 'Suggestions',
              items: widget.suggestions,
              afterHero: firstRow == 3,
              idOf: _workId,
              itemBuilder: (item, index) => PosterCard(
                key: ValueKey(
                  '${item.primary.server.machineIdentifier}:${item.primary.value.ratingKey}',
                ),
                imageUrl: PlexImageUrl.of(
                  item.primary.server,
                  item.primary.value.thumb,
                ),
                title: continueWatchingLabel(item.primary.value),
                onClick: () => widget.onSelectSuggestion(item),
                autofocus: index == 0 && suggestionsGetsFocus,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Partial is not empty" (DESIGN.md) — one or more servers not
  /// answering at connect time is a header line naming what happened, not
  /// an error state; only every server being unreachable takes the whole
  /// screen (NoServersReachable, screen 24).
  Widget _buildPartialOutageBanner() {
    final total = widget.servers.length + widget.unreachableResources.length;
    final names = widget.unreachableResources.map((r) => r.name).join(', ');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xxxl.du(context),
        AppSpacing.lg.du(context),
        AppSpacing.xxxl.du(context),
        0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            PhosphorIconsRegular.warning,
            size: 20,
            tint: AppColors.warning,
          ),
          SizedBox(width: AppSpacing.sm.du(context)),
          Flexible(
            child: AppText(
              '$names unreachable — ${widget.servers.length} of $total shown',
              color: AppColors.warning,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Screen 01's first viewport: the top in-progress item promoted to the
  /// resume hero, with the Watch Together bar and whatever else is in
  /// progress pinned to its foot. Focus reaching the hero's own actions
  /// scrolls Home back to the very top, so coming up from a row below
  /// always reveals the whole hero rather than just the button.
  Widget _buildHeroViewport(
    double viewportHeight,
    bool continueWatchingGetsFocus,
    Widget? watchTogetherBar,
  ) {
    final hero = widget.onDeck.first;
    final moreInProgress = widget.onDeck.length > 1
        ? widget.onDeck.sublist(1)
        : const <FoldedWork<PlexOnDeckItem>>[];

    return HomeHero(
      item: hero,
      height: viewportHeight,
      onResume: () => widget.onResume(hero),
      onWatchTogether: widget.onHeroWatchTogether,
      resumeFocusNode: moreInProgress.isEmpty
          ? _continueWatchingRowFocus
          : null,
      autofocus: continueWatchingGetsFocus,
      onActionsFocused: () {
        // After the traversal's own ensureVisible has started, so this
        // animation replaces it rather than racing it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _homeScrollController.hasClients &&
              _homeScrollController.offset > 0) {
            _homeScrollController.animateTo(
              0,
              duration: AppMotion.rowScroll,
              curve: AppMotion.enter,
            );
          }
        });
      },
      footer: [
        ?watchTogetherBar,
        if (moreInProgress.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(left: AppSpacing.safeX.du(context)),
                child: AppText(
                  'More in progress',
                  style: AppTypography.rowLabel,
                ),
              ),
              // Row label → cards is 16; the ListView's own 12 du top
              // headroom (rowHeadroom / 2) makes up the rest.
              SizedBox(
                height: (AppSpacing.lg - AppSpacing.rowHeadroom / 2).du(
                  context,
                ),
              ),
              SizedBox(
                // 209 card + 12 + 26 title + 3 + 24 caption, +8 for
                // 16:9's 209.25 and text line boxes rounding up at
                // fractional scales, plus rowHeadroom so a focused
                // card's scale and frame are never clipped.
                height: (209 + 12 + 26 + 3 + 24 + 8 + AppSpacing.rowHeadroom)
                    .du(context),
                child: EdgeFadeRow(
                  child: RowEndStop(
                    child: ListView.separated(
                      key: const PageStorageKey('home-row-in-progress'),
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.safeX.du(context),
                        vertical: (AppSpacing.rowHeadroom / 2).du(context),
                      ),
                      itemCount: moreInProgress.length,
                      separatorBuilder: (context, index) =>
                          SizedBox(width: AppSpacing.cardGap.du(context)),
                      itemBuilder: (context, index) {
                        final item = moreInProgress[index];
                        return RememberFocus(
                          key: ValueKey(_workId(item)),
                          id: 'home:in-progress:${_workId(item)}',
                          child: ContinueWatchingPoster(
                            item: item,
                            onResume: () => widget.onResume(item),
                            onRemove: () => widget.onRemove(item),
                            focusNode: index == 0
                                ? _continueWatchingRowFocus
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

String _workId(FoldedWork<Object> work) {
  final primary = work.primary;
  final key = switch (primary.value) {
    PlexOnDeckItem(:final ratingKey) => ratingKey,
    PlexLibraryItem(:final ratingKey) => ratingKey,
    _ => '${primary.value.hashCode}',
  };
  return '${primary.server.machineIdentifier}:$key';
}

/// A titled horizontal row that
/// renders nothing at all when empty (distinct from Continue Watching,
/// which always shows its title + an explicit empty-state message).
class _HomeRow<T> extends StatelessWidget {
  final String title;
  final List<T> items;

  /// The first row under the hero: the hero already leaves its bottom
  /// margin, so this row adds none of its own above its title — the two
  /// together doubled the gap.
  final bool afterHero;
  final String Function(T item) idOf;
  final Widget Function(T item, int index) itemBuilder;

  const _HomeRow({
    required this.title,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    this.afterHero = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _ScrollSectionIntoView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.safeX.du(context),
              top: afterHero ? 0 : AppSpacing.xxxl.du(context),
            ),
            child: AppText(title, style: AppTypography.rowLabel),
          ),
          // Label → cards is 16; the row's rowHeadroom/2 makes up the rest.
          SizedBox(
            height: (AppSpacing.lg - AppSpacing.rowHeadroom / 2).du(context),
          ),
          SizedBox(
            height: (posterCardExtent + AppSpacing.rowHeadroom).du(context),
            child: EdgeFadeRow(
              child: RowEndStop(
                child: ListView.separated(
                  key: PageStorageKey('home-row-$title'),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.safeX.du(context),
                    vertical: (AppSpacing.rowHeadroom / 2).du(context),
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(width: AppSpacing.cardGap.du(context)),
                  itemBuilder: (context, index) {
                    final id = idOf(items[index]);
                    // The same title can sit in two rows, so the row is
                    // part of what's remembered.
                    return RememberFocus(
                      key: ValueKey(id),
                      id: 'home:$title:$id',
                      child: itemBuilder(items[index], index),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The default focus-follow-scroll only guarantees the focused card's own
/// bounding box is visible — not a sibling header sitting above it in the
/// same section. Navigating back up into a row from below could leave its
/// title scrolled just out of view even though the row itself is showing.
/// Explicitly scrolling the whole section (header included) into view
/// whenever focus lands anywhere inside it fixes that.
class _ScrollSectionIntoView extends StatelessWidget {
  final Widget child;

  const _ScrollSectionIntoView({required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (hasFocus)
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 200),
          );
      },
      child: child,
    );
  }
}
