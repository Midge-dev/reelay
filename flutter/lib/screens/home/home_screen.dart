import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../library/poster_card.dart';
import 'home_hero.dart';
import 'home_posters.dart';
import 'watch_together_bar.dart';
import 'watch_together_row.dart' show MergedRoom;

const _rowStaggerPeriod = 6;
const _watchTogetherFocusQuietMs = 1200;
const _watchTogetherScrollDurationMs = 1100;

/// Ports ui/home/HomeScreen.kt — the most complex screen in the app.
/// Cascading "which row gets initial focus" priority (only the first
/// non-empty row among Watch Together > Watchlist > Continue Watching >
/// Recently Finished > Recently Added > Suggestions), a debounced
/// scroll-to-top for Watch Together once D-pad input goes quiet, and
/// checklist item #2 (removing a focused list item must reclaim focus
/// *within that row*) via [_ReclaimFocusOnRemoval] — the one checklist
/// item the flutter-reelay PoC left genuinely untested, now real.
class HomeScreen extends StatefulWidget {
  final PlexServer server;
  final List<PlexOnDeckItem> onDeck;
  final List<PlexLibraryItem> recentlyAdded;
  final List<PlexOnDeckItem> recentActivity;
  final List<PlexOnDeckItem> suggestions;
  final List<PlexWatchlistItem> watchlist;
  final List<MergedRoom> liveRooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final Future<bool> Function(MergedRoom) onEndSession;
  final ValueChanged<MergedRoom> onSelectRoom;
  final ValueChanged<PlexOnDeckItem> onResume;
  final ValueChanged<PlexOnDeckItem> onRemove;
  final ValueChanged<PlexWatchlistItem> onSelectWatchlistItem;
  final ValueChanged<PlexWatchlistItem> onRemoveFromWatchlist;
  final ValueChanged<PlexLibraryItem> onSelectRecentlyAdded;
  final ValueChanged<PlexOnDeckItem> onSelectRecentActivity;
  final ValueChanged<PlexOnDeckItem> onSelectSuggestion;
  final ValueChanged<PlexOnDeckItem>? onHeroWatchTogether;

  const HomeScreen({
    super.key,
    required this.server,
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

  /// Ports HomeScreen.kt's `ReclaimFocusOnRemoval` — if a row shrank (an
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
    final watchTogetherGetsFocus = widget.liveRooms.isNotEmpty;
    final watchlistGetsFocus =
        !watchTogetherGetsFocus && widget.watchlist.isNotEmpty;
    final continueWatchingGetsFocus =
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        widget.onDeck.isNotEmpty;
    final recentActivityGetsFocus =
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        widget.recentActivity.isNotEmpty;
    final recentlyAddedGetsFocus =
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        !recentActivityGetsFocus &&
        widget.recentlyAdded.isNotEmpty;
    final suggestionsGetsFocus =
        !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        !recentActivityGetsFocus &&
        !recentlyAddedGetsFocus &&
        widget.suggestions.isNotEmpty;

    final watchlistReversed = widget.watchlist.reversed.toList();

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        controller: _homeScrollController,
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _buildContinueWatchingSection(continueWatchingGetsFocus),
          if (widget.liveRooms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxxl,
                0,
                AppSpacing.xxxl,
                AppSpacing.xl,
              ),
              child: WatchTogetherBar(
                rooms: widget.liveRooms,
                myRoomId: widget.myRoomId,
                hostedRoomIds: widget.hostedRoomIds,
                onEndSession: widget.onEndSession,
                onSelectRoom: widget.onSelectRoom,
                focusNode: _watchTogetherRowFocus,
                autofocus: watchTogetherGetsFocus,
              ),
            ),
          _HomeRow<PlexWatchlistItem>(
            title: 'Watchlist',
            items: watchlistReversed,
            itemBuilder: (entry, index) => WatchlistPoster(
              key: ValueKey(entry.ratingKey),
              server: widget.server,
              entry: entry,
              onClick: () => widget.onSelectWatchlistItem(entry),
              onRemove: () => widget.onRemoveFromWatchlist(entry),
              focusNode: index == 0 ? _watchlistRowFocus : null,
              autofocus: index == 0 && watchlistGetsFocus,
              staggerDelayMs: (index % _rowStaggerPeriod) * 120,
            ),
          ),
          _HomeRow<PlexOnDeckItem>(
            title: 'Recently Finished Watching',
            items: widget.recentActivity,
            itemBuilder: (item, index) => PosterCard(
              key: ValueKey(item.ratingKey),
              imageUrl: PlexImageUrl.of(widget.server, item.thumb),
              title: continueWatchingLabel(item),
              onClick: () => widget.onSelectRecentActivity(item),
              autofocus: index == 0 && recentActivityGetsFocus,
              staggerDelayMs: (index % _rowStaggerPeriod) * 120,
            ),
          ),
          _HomeRow<PlexLibraryItem>(
            title: 'Recently Added',
            items: widget.recentlyAdded,
            itemBuilder: (item, index) => PosterCard(
              key: ValueKey(item.ratingKey),
              imageUrl: PlexImageUrl.of(widget.server, item.thumb),
              title: recentlyAddedLabel(item),
              onClick: () => widget.onSelectRecentlyAdded(item),
              autofocus: index == 0 && recentlyAddedGetsFocus,
              staggerDelayMs: (index % _rowStaggerPeriod) * 120,
            ),
          ),
          _HomeRow<PlexOnDeckItem>(
            title: 'Suggestions',
            items: widget.suggestions,
            itemBuilder: (item, index) => PosterCard(
              key: ValueKey(item.ratingKey),
              imageUrl: PlexImageUrl.of(widget.server, item.thumb),
              title: continueWatchingLabel(item),
              onClick: () => widget.onSelectSuggestion(item),
              autofocus: index == 0 && suggestionsGetsFocus,
              staggerDelayMs: (index % _rowStaggerPeriod) * 120,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty: the old "Continue Watching" row, kept verbatim — a first-run
  /// empty is a fact, not a failure (DESIGN.md's empty/error section), so
  /// it's a plain heading and one sentence, not a hero with nothing to show.
  /// Non-empty: the top item is promoted to [HomeHero] — real data, no
  /// invented curation — and whatever's left becomes the "More in
  /// progress" row, per the Nocturne redesign's screen 01.
  Widget _buildContinueWatchingSection(bool continueWatchingGetsFocus) {
    if (widget.onDeck.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xxxl,
          top: AppSpacing.xxxl,
          bottom: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText('Continue Watching', style: AppTypography.rowLabel),
            SizedBox(height: AppSpacing.md),
            AppText('Nothing in progress right now.'),
          ],
        ),
      );
    }

    final hero = widget.onDeck.first;
    final moreInProgress = widget.onDeck.length > 1
        ? widget.onDeck.sublist(1)
        : const <PlexOnDeckItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeHero(
          server: widget.server,
          item: hero,
          onResume: () => widget.onResume(hero),
          onWatchTogether: widget.onHeroWatchTogether,
          resumeFocusNode: moreInProgress.isEmpty
              ? _continueWatchingRowFocus
              : null,
          autofocus: continueWatchingGetsFocus,
        ),
        if (moreInProgress.isNotEmpty)
          _ScrollSectionIntoView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.xxxl,
                    top: AppSpacing.xl,
                    bottom: AppSpacing.lg,
                  ),
                  child: AppText(
                    'More in progress',
                    style: AppTypography.rowLabel,
                  ),
                ),
                SizedBox(
                  // +24 over the card's own content height: EdgeFadeRow's
                  // ShaderMask only fades within its own layout bounds, and
                  // a focused card's scale overflow (let through by
                  // Clip.none below) painted outside a tightly-fit box
                  // escapes the mask entirely — the top of a focused card
                  // looked unfaded. Real vertical headroom, not just
                  // Clip.none, keeps the whole scaled card inside the
                  // mask's bounds. Content height: 209 image + 12 padding +
                  // a label line (26) + a 3px gap + a caption line (24),
                  // +24 headroom. Confirmed on-device (Shield): 296 clipped
                  // by ~2px, so this carries a few extra for safety.
                  height: 304,
                  child: EdgeFadeRow(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // Compose doesn't clip a Row's children to its own
                      // bounds by default; Flutter's ListView does. Without
                      // this, a card's focus-scale grows past this
                      // SizedBox's fixed height and gets hard-clipped at
                      // the top/bottom edge.
                      clipBehavior: Clip.none,
                      // 48, not 32: the focused card's scale/glow needs
                      // headroom against the screen edge itself, not just
                      // the row's own bounds. Vertical 12 matches the +24
                      // SizedBox headroom above.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 12,
                      ),
                      itemCount: moreInProgress.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 24),
                      itemBuilder: (context, index) {
                        final item = moreInProgress[index];
                        return ContinueWatchingPoster(
                          key: ValueKey(item.ratingKey),
                          server: widget.server,
                          item: item,
                          onResume: () => widget.onResume(item),
                          onRemove: () => widget.onRemove(item),
                          focusNode: index == 0
                              ? _continueWatchingRowFocus
                              : null,
                          staggerDelayMs: (index % _rowStaggerPeriod) * 120,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ports HomeScreen.kt's generic `HomeRow` — a titled horizontal row that
/// renders nothing at all when empty (distinct from Continue Watching,
/// which always shows its title + an explicit empty-state message).
class _HomeRow<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Widget Function(T item, int index) itemBuilder;

  const _HomeRow({
    required this.title,
    required this.items,
    required this.itemBuilder,
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
            padding: const EdgeInsets.only(
              left: AppSpacing.xxxl,
              top: AppSpacing.xxl,
              bottom: AppSpacing.xl,
            ),
            child: AppText(title, style: AppTypography.rowLabel),
          ),
          SizedBox(
            // See the matching comment on Continue Watching's SizedBox above.
            // Content height 288 (240 poster + 16 padding + a Nocturne body
            // line at ~32) + 24 headroom.
            height: 316,
            child: EdgeFadeRow(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // See the matching comment on Continue Watching's ListView above.
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 12,
                ),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 24),
                itemBuilder: (context, index) =>
                    itemBuilder(items[index], index),
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
