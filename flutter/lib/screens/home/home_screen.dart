import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../library/poster_card.dart';
import 'home_posters.dart';
import 'watch_together_row.dart';

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
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _homeScrollController = ScrollController();
  final _watchTogetherScrollController = ScrollController();

  final _watchTogetherRowFocus = FocusNode(debugLabel: 'home-watch-together-row');
  final _watchlistRowFocus = FocusNode(debugLabel: 'home-watchlist-row');
  final _continueWatchingRowFocus = FocusNode(debugLabel: 'home-continue-watching-row');

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
    _reclaimFocusOnRemoval(widget.liveRooms.length, _prevLiveRoomsCount, _watchTogetherRowFocus);
    _reclaimFocusOnRemoval(widget.watchlist.length, _prevWatchlistCount, _watchlistRowFocus);
    _reclaimFocusOnRemoval(widget.onDeck.length, _prevOnDeckCount, _continueWatchingRowFocus);
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
    _watchTogetherScrollController.dispose();
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
  void _reclaimFocusOnRemoval(int newSize, int previousSize, FocusNode rowFocus) {
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
      await Future.delayed(Duration(milliseconds: _watchTogetherFocusQuietMs - elapsed));
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
    final watchlistGetsFocus = !watchTogetherGetsFocus && widget.watchlist.isNotEmpty;
    final continueWatchingGetsFocus = !watchTogetherGetsFocus && !watchlistGetsFocus && widget.onDeck.isNotEmpty;
    final recentActivityGetsFocus =
        !watchTogetherGetsFocus && !watchlistGetsFocus && !continueWatchingGetsFocus && widget.recentActivity.isNotEmpty;
    final recentlyAddedGetsFocus = !watchTogetherGetsFocus &&
        !watchlistGetsFocus &&
        !continueWatchingGetsFocus &&
        !recentActivityGetsFocus &&
        widget.recentlyAdded.isNotEmpty;
    final suggestionsGetsFocus = !watchTogetherGetsFocus &&
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
          WatchTogetherRow(
            server: widget.server,
            rooms: widget.liveRooms,
            myRoomId: widget.myRoomId,
            hostedRoomIds: widget.hostedRoomIds,
            onEndSession: widget.onEndSession,
            onSelectRoom: widget.onSelectRoom,
            firstCardAutofocus: watchTogetherGetsFocus,
            rowAnchorFocusNode: _watchTogetherRowFocus,
            scrollController: _watchTogetherScrollController,
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
          _buildContinueWatchingSection(continueWatchingGetsFocus),
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

  Widget _buildContinueWatchingSection(bool continueWatchingGetsFocus) {
    return _ScrollSectionIntoView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 32, top: 32, bottom: 16),
            child: AppText('Continue Watching', style: AppTypography.titleLarge),
          ),
          if (widget.onDeck.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 32),
              child: AppText('Nothing in progress right now.'),
            )
          else
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                itemCount: widget.onDeck.length,
                separatorBuilder: (context, index) => const SizedBox(width: 24),
                itemBuilder: (context, index) {
                  final item = widget.onDeck[index];
                  return ContinueWatchingPoster(
                    key: ValueKey(item.ratingKey),
                    server: widget.server,
                    item: item,
                    onResume: () => widget.onResume(item),
                    onRemove: () => widget.onRemove(item),
                    focusNode: index == 0 ? _continueWatchingRowFocus : null,
                    autofocus: index == 0 && continueWatchingGetsFocus,
                    staggerDelayMs: (index % _rowStaggerPeriod) * 120,
                  );
                },
              ),
            ),
        ],
      ),
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

  const _HomeRow({required this.title, required this.items, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _ScrollSectionIntoView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 32, bottom: 28),
            child: AppText(title, style: AppTypography.titleLarge),
          ),
          SizedBox(
            height: 278,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 24),
              itemBuilder: (context, index) => itemBuilder(items[index], index),
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
        if (hasFocus) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 200));
      },
      child: child,
    );
  }
}
