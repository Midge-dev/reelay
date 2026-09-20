import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/loading_screen.dart';
import 'genre_filter_panel.dart';
import 'library_filters.dart';
import 'library_tab.dart';
import 'poster_card.dart';
import 'search_keyboard.dart';

const _gridColumns = 5;
const _posterCardHeight = 278.0;

enum BrowseTab { all, genre, collections, search }

/// Ports ui/library/LibraryScreen.kt — the single most focus-logic-heavy
/// screen in the app: a tabbed browse UI (All/Genres/Collections/Search)
/// with a custom on-screen keyboard and a genre/decade/date-added filter
/// panel. State resets whenever `selectedSection.key` changes (a new
/// library section was picked in the nav rail), mirroring Kotlin's
/// `remember(selectedSection.key)` pattern via didUpdateWidget.
class LibraryScreen extends StatefulWidget {
  final PlexServer server;
  final PlexSection selectedSection;
  final List<PlexLibraryItem> items;
  final ValueChanged<PlexLibraryItem> onSelectItem;
  final Future<List<PlexCollection>> Function() loadCollections;
  final ValueChanged<PlexCollection> onSelectCollection;

  const LibraryScreen({
    super.key,
    required this.server,
    required this.selectedSection,
    required this.items,
    required this.onSelectItem,
    required this.loadCollections,
    required this.onSelectCollection,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _genreFilter;
  int? _decadeFilter;
  DateAddedBucket? _dateAddedFilter;
  BrowseTab _browseTab = BrowseTab.all;
  List<PlexCollection>? _collections;
  String _searchQuery = '';

  final _allTabScrollController = ScrollController();
  final _genreResultsScrollController = ScrollController();
  final _collectionsScrollController = ScrollController();
  final _searchResultsScrollController = ScrollController();
  final _allTabFocus = FocusNode(debugLabel: 'tab-all');
  final _genreTabFocus = FocusNode(debugLabel: 'tab-genre');
  final _collectionsTabFocus = FocusNode(debugLabel: 'tab-collections');
  final _searchTabFocus = FocusNode(debugLabel: 'tab-search');
  final _searchFirstKeyFocus = FocusNode(debugLabel: 'search-key-first');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tabFocusFor(_browseTab).requestFocus());
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSection.key != widget.selectedSection.key) {
      setState(() {
        _genreFilter = null;
        _decadeFilter = null;
        _dateAddedFilter = null;
        _browseTab = BrowseTab.all;
        _collections = null;
        _searchQuery = '';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _allTabFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _allTabScrollController.dispose();
    _genreResultsScrollController.dispose();
    _collectionsScrollController.dispose();
    _searchResultsScrollController.dispose();
    _allTabFocus.dispose();
    _genreTabFocus.dispose();
    _collectionsTabFocus.dispose();
    _searchTabFocus.dispose();
    _searchFirstKeyFocus.dispose();
    super.dispose();
  }

  FocusNode _tabFocusFor(BrowseTab tab) => switch (tab) {
        BrowseTab.all => _allTabFocus,
        BrowseTab.genre => _genreTabFocus,
        BrowseTab.collections => _collectionsTabFocus,
        BrowseTab.search => _searchTabFocus,
      };

  void _selectTab(BrowseTab tab) {
    setState(() => _browseTab = tab);
    if (tab == BrowseTab.collections && _collections == null) _loadCollections();
    // The tab button itself keeps focus through this setState — explicit
    // request needed, same reasoning as the matching player_screen.dart fix.
    if (tab == BrowseTab.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFirstKeyFocus.requestFocus();
      });
    }
  }

  Future<void> _loadCollections() async {
    List<PlexCollection> result;
    try {
      result = await widget.loadCollections();
    } catch (_) {
      result = const [];
    }
    if (mounted) setState(() => _collections = result);
  }

  /// Wraps a vertically-scrolling poster grid with the scroll-aware
  /// top/bottom fade and a hard clip at its own bounds — the grid's own
  /// Clip.none (needed so a focused card's scale-up isn't clipped by its
  /// own cell) would otherwise let scrolled-past rows paint straight
  /// through into whatever sits above it (the tab bar, a header) once they
  /// scroll behind it. The top fade only shows once actually scrolled, so
  /// it doesn't just dim the first row for no reason at rest.
  Widget _fadingGrid({required ScrollController controller, required Widget grid}) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => EdgeFadeRow(
          axis: Axis.vertical,
          fadeStart: controller.hasClients && controller.offset > 0,
          // Matches PosterCard's ensureRowVisible peek extent, so the gap
          // it reserves at the bottom of a scroll and the band that
          // actually fades line up.
          fadeWidth: posterRowPeekExtent,
          child: child!,
        ),
        child: grid,
      ),
    );
  }

  KeyEventResult _trapUpAboveTabs(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final availableGenres = widget.items.expand((i) => i.genres.map((g) => g.tag)).toSet().toList()..sort();
    final availableDecades = widget.items.map(decadeOf).whereType<int>().toSet().toList()..sort((a, b) => b.compareTo(a));
    final genreResults = applyLibraryFilters(
      items: widget.items,
      query: '',
      sortMode: SortMode.title,
      genre: _genreFilter,
      decade: _decadeFilter,
      dateAddedBucket: _dateAddedFilter,
    );
    final searchResults = _searchQuery.trim().isEmpty
        ? const <PlexLibraryItem>[]
        : applyLibraryFilters(items: widget.items, query: _searchQuery, sortMode: SortMode.title);

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            canRequestFocus: false,
            onKeyEvent: _trapUpAboveTabs,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, top: 16, right: 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LibraryTab(label: 'All', selected: _browseTab == BrowseTab.all, focusNode: _allTabFocus, onClick: () => _selectTab(BrowseTab.all)),
                  const SizedBox(width: 6),
                  LibraryTab(label: 'Genres', selected: _browseTab == BrowseTab.genre, focusNode: _genreTabFocus, onClick: () => _selectTab(BrowseTab.genre)),
                  const SizedBox(width: 6),
                  LibraryTab(label: 'Collections', selected: _browseTab == BrowseTab.collections, focusNode: _collectionsTabFocus, onClick: () => _selectTab(BrowseTab.collections)),
                  const SizedBox(width: 6),
                  LibraryTab(label: 'Search', selected: _browseTab == BrowseTab.search, focusNode: _searchTabFocus, onClick: () => _selectTab(BrowseTab.search)),
                ],
              ),
            ),
          ),
          Container(height: 2, color: AppColors.surfaceVariant),
          Expanded(
            child: switch (_browseTab) {
              BrowseTab.all => _buildAllTab(),
              BrowseTab.genre => _buildGenreTab(availableGenres, availableDecades, genreResults),
              BrowseTab.collections => _buildCollectionsTab(),
              BrowseTab.search => _buildSearchTab(searchResults),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAllTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
          child: Row(
            children: [
              AppText(widget.selectedSection.title, style: AppTypography.titleMedium),
              const Spacer(),
              AppText('${widget.items.length} titles · A–Z', color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
        Expanded(
          child: widget.items.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: AppText('Nothing in this library yet.'))
              : _fadingGrid(
                  controller: _allTabScrollController,
                  grid: GridView.builder(
                    controller: _allTabScrollController,
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 48),
                    clipBehavior: Clip.none,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _gridColumns,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 24,
                      mainAxisExtent: _posterCardHeight,
                    ),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return PosterCard(
                        key: ValueKey(item.ratingKey),
                        imageUrl: PlexImageUrl.of(widget.server, item.thumb),
                        title: item.title,
                        autofocus: index == 0,
                        staggerDelayMs: (index % _gridColumns) * 120,
                        onClick: () => widget.onSelectItem(item),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGenreTab(List<String> availableGenres, List<int> availableDecades, List<PlexLibraryItem> genreResults) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GenreFilterPanel(
          items: widget.items,
          availableGenres: availableGenres,
          availableDecades: availableDecades,
          genreFilter: _genreFilter,
          decadeFilter: _decadeFilter,
          dateAddedFilter: _dateAddedFilter,
          aboveFocusNode: _genreTabFocus,
          onGenreSelect: (g) => setState(() => _genreFilter = _genreFilter == g ? null : g),
          onDecadeSelect: (d) => setState(() => _decadeFilter = _decadeFilter == d ? null : d),
          onDateAddedSelect: (b) => setState(() => _dateAddedFilter = _dateAddedFilter == b ? null : b),
          onClearAll: () => setState(() {
            _genreFilter = null;
            _decadeFilter = null;
            _dateAddedFilter = null;
          }),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_genreFilter != null) ...[AppliedFilterChip(label: formatGenreLabel(_genreFilter!)), const SizedBox(width: 12)],
                    if (_decadeFilter != null) ...[AppliedFilterChip(label: '${_decadeFilter}s'), const SizedBox(width: 12)],
                    if (_dateAddedFilter != null) ...[AppliedFilterChip(label: _dateAddedFilter!.label), const SizedBox(width: 12)],
                    const Spacer(),
                    AppText('${genreResults.length} titles · Sort: Title', color: AppColors.onSurfaceVariant),
                  ],
                ),
                Expanded(
                  child: genreResults.isEmpty
                      ? const Padding(padding: EdgeInsets.only(top: 24), child: AppText('Nothing matches these filters.'))
                      : _fadingGrid(
                          controller: _genreResultsScrollController,
                          grid: GridView.builder(
                            controller: _genreResultsScrollController,
                            // Unlike the All/Collections grids, this one has
                            // no padding of its own margin from the screen
                            // edge (its ancestor Padding already provides
                            // that) — but the new outer ClipRect still needs
                            // *some* slack inside it, or a focused card's
                            // scale-up has nowhere to bleed into on the left.
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
                            clipBehavior: Clip.none,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: _posterCardHeight,
                            ),
                            itemCount: genreResults.length,
                            itemBuilder: (context, index) {
                              final item = genreResults[index];
                              return PosterCard(
                                key: ValueKey(item.ratingKey),
                                imageUrl: PlexImageUrl.of(widget.server, item.thumb),
                                title: item.title,
                                autofocus: index == 0,
                                onClick: () => widget.onSelectItem(item),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionsTab() {
    final collections = _collections;
    if (collections == null) {
      return const LoadingScreen();
    }
    if (collections.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: AppText('No collections found'));
    }
    return _fadingGrid(
      controller: _collectionsScrollController,
      grid: GridView.builder(
        controller: _collectionsScrollController,
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
        clipBehavior: Clip.none,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridColumns,
          mainAxisSpacing: 24,
          crossAxisSpacing: 24,
          mainAxisExtent: _posterCardHeight,
        ),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final collection = collections[index];
          final childCount = collection.childCount;
          return PosterCard(
            key: ValueKey(collection.ratingKey),
            imageUrl: PlexImageUrl.of(widget.server, collection.thumb),
            title: collection.title,
            subtitle: childCount != null ? '$childCount title${childCount == 1 ? '' : 's'}' : null,
            autofocus: index == 0,
            onClick: () => widget.onSelectCollection(collection),
          );
        },
      ),
    );
  }

  Widget _buildSearchTab(List<PlexLibraryItem> searchResults) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.surfaceVariant, width: 2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: AppText(
                    _searchQuery.isEmpty ? 'Type a title…' : _searchQuery,
                    color: _searchQuery.isEmpty ? AppColors.onSurfaceVariant : AppColors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SearchKeyboard(
                  onChar: (c) => setState(() => _searchQuery += c),
                  onBackspace: () => setState(() => _searchQuery = _searchQuery.isEmpty ? '' : _searchQuery.substring(0, _searchQuery.length - 1)),
                  onClear: () => setState(() => _searchQuery = ''),
                  autofocus: true,
                  firstKeyFocusNode: _searchFirstKeyFocus,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    _searchQuery.trim().isEmpty ? 'Results' : 'Results · ${searchResults.length} titles for "$_searchQuery"',
                    color: AppColors.onSurfaceVariant,
                  ),
                  Expanded(
                    child: _searchQuery.trim().isEmpty
                        ? const SizedBox.shrink()
                        : _fadingGrid(
                            controller: _searchResultsScrollController,
                            grid: GridView.builder(
                              controller: _searchResultsScrollController,
                              // See the matching comment on the Genres tab's grid.
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
                              clipBehavior: Clip.none,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: _posterCardHeight,
                              ),
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final item = searchResults[index];
                                return PosterCard(
                                  key: ValueKey(item.ratingKey),
                                  imageUrl: PlexImageUrl.of(widget.server, item.thumb),
                                  title: item.title,
                                  onClick: () => widget.onSelectItem(item),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
