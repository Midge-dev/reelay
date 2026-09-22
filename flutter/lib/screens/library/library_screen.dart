import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../kit/button.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/app_state.dart' show SectionGroup;
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/click_to_type_text_field.dart';
import '../common/loading_screen.dart';
import 'genre_filter_panel.dart';
import 'library_filters.dart';
import 'poster_card.dart';

const _gridColumns = 7; // Foundations §03/tokens.json geometry.referenceColumns
// 160w*3/2 image (240) + 16 padding + label line (26) + optional caption
// line (24) = 306 in theory, but PosterCard's real measured height with a
// subtitle present (e.g. collection card counts) runs closer to 330 — the
// pre-existing constant undershot this, previously invisible only because
// the old Collections tab's widget test never exercised a real childCount.
const _posterCardHeight = 334.0;

enum _ViewMode { titles, collections }

enum _FilterKind { genre, decade, added, sort }

/// Ports ui/library/LibraryScreen.kt, rebuilt to match the Nocturne handoff's
/// screens 17-19: the old All/Genres/Collections/Search tab strip is gone
/// (see the handoff's own "LIBRARY · WHERE THE OLD TABS WENT" explainer —
/// All was never a distinct mode, Genres is a filter not a destination,
/// Search already exists in the rail at a wider scope). What remains is one
/// filter row — a Titles/Collections mode switch, Genre/Decade/Added/Sort
/// dropdown chips, and a text field that narrows the current grid — sitting
/// above a 7-column grid that never remounts on a filter change. State
/// resets whenever `selectedSection.key` changes, mirroring Kotlin's
/// `remember(selectedSection.key)` pattern via didUpdateWidget.
class LibraryScreen extends StatefulWidget {
  final List<ReachableServer> servers;
  final SectionGroup selectedSectionGroup;
  final List<Sourced<PlexLibraryItem>> items;
  final ValueChanged<Sourced<PlexLibraryItem>> onSelectItem;
  final Future<List<Sourced<PlexCollection>>> Function() loadCollections;
  final ValueChanged<Sourced<PlexCollection>> onSelectCollection;

  const LibraryScreen({
    super.key,
    required this.servers,
    required this.selectedSectionGroup,
    required this.items,
    required this.onSelectItem,
    required this.loadCollections,
    required this.onSelectCollection,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _ViewMode _viewMode = _ViewMode.titles;
  String? _genreFilter;
  int? _decadeFilter;
  DateAddedBucket? _dateAddedFilter;
  SortMode _sortMode = SortMode.title;
  _FilterKind? _openFilter;
  List<Sourced<PlexCollection>>? _collections;
  String _searchQuery = '';

  final _gridScrollController = ScrollController();
  final _collectionsScrollController = ScrollController();
  final _titlesModeFocus = FocusNode(debugLabel: 'library-mode-titles');
  final _collectionsModeFocus = FocusNode(
    debugLabel: 'library-mode-collections',
  );
  final _genreChipFocus = FocusNode(debugLabel: 'library-filter-genre');
  final _decadeChipFocus = FocusNode(debugLabel: 'library-filter-decade');
  final _addedChipFocus = FocusNode(debugLabel: 'library-filter-added');
  final _sortChipFocus = FocusNode(debugLabel: 'library-filter-sort');
  final _clearAllFocus = FocusNode(debugLabel: 'library-filter-clear-all');
  final _searchFieldFocus = FocusNode(debugLabel: 'library-search-field');

  final _stackKey = GlobalKey();
  final _genreChipKey = GlobalKey();
  final _decadeChipKey = GlobalKey();
  final _addedChipKey = GlobalKey();
  final _sortChipKey = GlobalKey();
  Offset? _panelAnchor;

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSectionGroup.key != widget.selectedSectionGroup.key) {
      setState(() {
        _viewMode = _ViewMode.titles;
        _genreFilter = null;
        _decadeFilter = null;
        _dateAddedFilter = null;
        _sortMode = SortMode.title;
        _openFilter = null;
        _collections = null;
        _searchQuery = '';
      });
    }
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    _collectionsScrollController.dispose();
    _titlesModeFocus.dispose();
    _collectionsModeFocus.dispose();
    _genreChipFocus.dispose();
    _decadeChipFocus.dispose();
    _addedChipFocus.dispose();
    _sortChipFocus.dispose();
    _clearAllFocus.dispose();
    _searchFieldFocus.dispose();
    super.dispose();
  }

  GlobalKey _chipKeyFor(_FilterKind kind) => switch (kind) {
    _FilterKind.genre => _genreChipKey,
    _FilterKind.decade => _decadeChipKey,
    _FilterKind.added => _addedChipKey,
    _FilterKind.sort => _sortChipKey,
  };

  void _selectMode(_ViewMode mode) {
    setState(() {
      _viewMode = mode;
      _openFilter = null;
    });
    if (mode == _ViewMode.collections && _collections == null) {
      _loadCollections();
    }
  }

  Future<void> _loadCollections() async {
    List<Sourced<PlexCollection>> result;
    try {
      result = await widget.loadCollections();
    } catch (_) {
      result = const [];
    }
    if (mounted) setState(() => _collections = result);
  }

  void _toggleFilter(_FilterKind kind) {
    final opening = _openFilter != kind;
    setState(() => _openFilter = opening ? kind : null);
    if (!opening) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stackBox =
          _stackKey.currentContext?.findRenderObject() as RenderBox?;
      final chipBox =
          _chipKeyFor(kind).currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null || chipBox == null) return;
      final chipTopLeft = chipBox.localToGlobal(
        Offset.zero,
        ancestor: stackBox,
      );
      setState(
        () => _panelAnchor = Offset(
          chipTopLeft.dx,
          chipTopLeft.dy + chipBox.size.height + 8.du(context),
        ),
      );
    });
  }

  void _closeFilter() => setState(() => _openFilter = null);

  /// Wraps a vertically-scrolling poster grid with the scroll-aware
  /// top/bottom fade and a hard clip at its own bounds — the grid's own
  /// Clip.none (needed so a focused card's scale-up isn't clipped by its
  /// own cell) would otherwise let scrolled-past rows paint straight
  /// through into whatever sits above it (the filter row) once they
  /// scroll behind it. The top fade only shows once actually scrolled, so
  /// it doesn't just dim the first row for no reason at rest.
  Widget _fadingGrid({
    required ScrollController controller,
    required Widget grid,
  }) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => EdgeFadeRow(
          axis: Axis.vertical,
          fadeStart: controller.hasClients && controller.offset > 0,
          fadeWidth: posterRowPeekExtent,
          child: child!,
        ),
        child: grid,
      ),
    );
  }

  KeyEventResult _trapUpAboveFilterRow(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// [applyLibraryFilters] (library_filters.dart) works on bare
  /// PlexLibraryItems and stays that way — per the design handoff's own
  /// note, it's "unchanged, this is purely how the filters are surfaced."
  /// This unwraps for filtering, then maps the (identity-preserved) results
  /// back to their [Sourced] wrapper for rendering.
  List<Sourced<PlexLibraryItem>> _filteredItems() {
    final byIdentity = {for (final s in widget.items) s.value: s};
    final bareResults = applyLibraryFilters(
      items: widget.items.map((s) => s.value).toList(),
      query: _searchQuery,
      sortMode: _sortMode,
      genre: _genreFilter,
      decade: _decadeFilter,
      dateAddedBucket: _dateAddedFilter,
    );
    return bareResults.map((i) => byIdentity[i]!).toList();
  }

  List<PlexLibraryItem> get _bareItems => widget.items.map((s) => s.value).toList();

  String get _serverLabel {
    final ids = widget.selectedSectionGroup.sectionsByServerId.keys;
    final names = ids
        .map((id) => widget.servers.firstWhereOrNull((s) => s.server.machineIdentifier == id)?.server.name)
        .whereType<String>()
        .toList();
    if (names.length == 1) return 'Plex · ${names.single}';
    return 'Plex · ${names.length} servers';
  }

  @override
  Widget build(BuildContext context) {
    final bareItems = widget.items.map((s) => s.value).toList();
    final availableGenres =
        bareItems.expand((i) => i.genres.map((g) => g.tag)).toSet().toList()
          ..sort();
    final availableDecades =
        bareItems.map(decadeOf).whereType<int>().toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    final titleResults = _filteredItems();
    final collections = _collections;
    final collectionResults = collections == null
        ? null
        : (_searchQuery.trim().isEmpty
              ? collections
              : collections
                    .where(
                      (c) => c.value.title.toLowerCase().contains(
                        _searchQuery.trim().toLowerCase(),
                      ),
                    )
                    .toList());

    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        key: _stackKey,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(32.du(context), 24.du(context), 32.du(context), 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AppText(
                      widget.selectedSectionGroup.title,
                      style: AppTypography.title1,
                    ),
                    SizedBox(width: 18.du(context)),
                    AppText(
                      _serverLabel,
                      color: AppColors.ink3,
                    ),
                    const Spacer(),
                    AppText(
                      _summaryText(
                        titleResults.length,
                        collectionResults?.length,
                      ),
                      color: AppColors.ink3,
                    ),
                  ],
                ),
                SizedBox(height: 22.du(context)),
                Focus(
                  canRequestFocus: false,
                  onKeyEvent: _trapUpAboveFilterRow,
                  child: _buildFilterRow(availableGenres, availableDecades),
                ),
                SizedBox(height: 22.du(context)),
                Expanded(
                  child: _viewMode == _ViewMode.titles
                      ? _buildTitlesGrid(titleResults)
                      : _buildCollectionsGrid(collectionResults),
                ),
              ],
            ),
          ),
          if (_openFilter != null && _panelAnchor != null)
            Positioned(
              left: _panelAnchor!.dx,
              top: _panelAnchor!.dy,
              child: _buildOpenFilterPanel(availableGenres, availableDecades),
            ),
        ],
      ),
    );
  }

  String _summaryText(int titleCount, int? collectionCount) {
    if (_viewMode == _ViewMode.collections) {
      final count = collectionCount ?? 0;
      return '$count collection${count == 1 ? '' : 's'} · sorted by title';
    }
    final total = widget.items.length;
    final filtered = titleCount != total;
    final countText = filtered
        ? '$titleCount of $total titles'
        : '$total titles';
    return '$countText · sorted by ${_sortMode.label.toLowerCase()}';
  }

  Widget _buildFilterRow(
    List<String> availableGenres,
    List<int> availableDecades,
  ) {
    return SizedBox(
      height: 58.du(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ModeSwitch(
            mode: _viewMode,
            onSelect: _selectMode,
            titlesFocusNode: _titlesModeFocus,
            collectionsFocusNode: _collectionsModeFocus,
          ),
          SizedBox(width: 22.du(context)),
          Container(width: 1.du(context), height: 36.du(context), color: AppColors.line),
          SizedBox(width: 22.du(context)),
          // The filter-chip cluster scrolls horizontally rather than
          // overflowing — a library with every filter applied plus a long
          // genre name can exceed the row's remaining width even at 1920,
          // and D-pad focus already auto-scrolls a focused chip into view
          // (Scrollable.ensureVisible, same as every other scrollable rail
          // in this app), so nothing here is actually unreachable.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _buildFilterChips(),
              ),
            ),
          ),
          SizedBox(width: 22.du(context)),
          SizedBox(
            width: 260.du(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 20,
                  tint: AppColors.ink3,
                ),
                SizedBox(width: 12.du(context)),
                Expanded(
                  child: ClickToTypeTextField(
                    value: _searchQuery,
                    onValueChange: (v) => setState(() => _searchQuery = v),
                    focusNode: _searchFieldFocus,
                    hintText: _viewMode == _ViewMode.titles
                        ? 'Narrow this library'
                        : 'Narrow collections',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilterChips() {
    return [
      if (_viewMode == _ViewMode.titles) ...[
        _FilterChip(
          key: _genreChipKey,
          label: 'Genre',
          valueLabel: _genreFilter != null
              ? formatGenreLabel(_genreFilter!)
              : null,
          open: _openFilter == _FilterKind.genre,
          focusNode: _genreChipFocus,
          onClick: () => _toggleFilter(_FilterKind.genre),
        ),
        SizedBox(width: 12.du(context)),
        _FilterChip(
          key: _decadeChipKey,
          label: 'Decade',
          valueLabel: _decadeFilter != null ? '${_decadeFilter}s' : null,
          open: _openFilter == _FilterKind.decade,
          focusNode: _decadeChipFocus,
          onClick: () => _toggleFilter(_FilterKind.decade),
        ),
        SizedBox(width: 12.du(context)),
        _FilterChip(
          key: _addedChipKey,
          label: 'Added',
          valueLabel: _dateAddedFilter?.label,
          open: _openFilter == _FilterKind.added,
          focusNode: _addedChipFocus,
          onClick: () => _toggleFilter(_FilterKind.added),
        ),
        SizedBox(width: 12.du(context)),
      ],
      _FilterChip(
        key: _sortChipKey,
        label: 'Sort',
        valueLabel: _sortMode.label,
        alwaysShowValue: true,
        open: _openFilter == _FilterKind.sort,
        focusNode: _sortChipFocus,
        onClick: () => _toggleFilter(_FilterKind.sort),
      ),
      if (_viewMode == _ViewMode.titles && anyFilterApplied) ...[
        SizedBox(width: 12.du(context)),
        _ClearAllChip(
          focusNode: _clearAllFocus,
          onClick: () => setState(() {
            _genreFilter = null;
            _decadeFilter = null;
            _dateAddedFilter = null;
            _openFilter = null;
          }),
        ),
      ],
    ];
  }

  bool get anyFilterApplied =>
      _genreFilter != null || _decadeFilter != null || _dateAddedFilter != null;

  Widget _buildOpenFilterPanel(
    List<String> availableGenres,
    List<int> availableDecades,
  ) {
    switch (_openFilter!) {
      case _FilterKind.genre:
        return FilterDropdown(
          title: 'GENRE · ${availableGenres.length} IN THIS LIBRARY',
          aboveFocusNode: _genreChipFocus,
          options: [
            for (final genre in availableGenres)
              FilterOption(
                label: formatGenreLabel(genre),
                countLabel:
                    '${_bareItems.where((i) => i.genres.any((g) => g.tag == genre)).length}',
                applied: genre == _genreFilter,
                dimmed: applyLibraryFilters(
                  items: _bareItems,
                  query: '',
                  sortMode: SortMode.title,
                  genre: genre,
                  decade: _decadeFilter,
                  dateAddedBucket: _dateAddedFilter,
                ).isEmpty,
              ),
          ],
          onSelect: (index) {
            final genre = availableGenres[index];
            setState(() => _genreFilter = _genreFilter == genre ? null : genre);
            _closeFilter();
          },
        );
      case _FilterKind.decade:
        return FilterDropdown(
          title: 'DECADE · ${availableDecades.length} IN THIS LIBRARY',
          aboveFocusNode: _decadeChipFocus,
          options: [
            for (final decade in availableDecades)
              FilterOption(
                label: '${decade}s',
                countLabel:
                    '${_bareItems.where((i) => decadeOf(i) == decade).length}',
                applied: decade == _decadeFilter,
                dimmed: applyLibraryFilters(
                  items: _bareItems,
                  query: '',
                  sortMode: SortMode.title,
                  genre: _genreFilter,
                  decade: decade,
                  dateAddedBucket: _dateAddedFilter,
                ).isEmpty,
              ),
          ],
          onSelect: (index) {
            final decade = availableDecades[index];
            setState(
              () => _decadeFilter = _decadeFilter == decade ? null : decade,
            );
            _closeFilter();
          },
        );
      case _FilterKind.added:
        return FilterDropdown(
          title: 'ADDED',
          aboveFocusNode: _addedChipFocus,
          options: [
            for (final bucket in DateAddedBucket.values)
              FilterOption(
                label: bucket.label,
                applied: bucket == _dateAddedFilter,
                dimmed: applyLibraryFilters(
                  items: _bareItems,
                  query: '',
                  sortMode: SortMode.title,
                  genre: _genreFilter,
                  decade: _decadeFilter,
                  dateAddedBucket: bucket,
                ).isEmpty,
              ),
          ],
          onSelect: (index) {
            final bucket = DateAddedBucket.values[index];
            setState(
              () =>
                  _dateAddedFilter = _dateAddedFilter == bucket ? null : bucket,
            );
            _closeFilter();
          },
        );
      case _FilterKind.sort:
        return FilterDropdown(
          title: 'SORT',
          aboveFocusNode: _sortChipFocus,
          footerHint: 'Select applies · Back closes and keeps what you picked',
          options: [
            for (final mode in SortMode.values)
              FilterOption(label: mode.label, applied: mode == _sortMode),
          ],
          onSelect: (index) {
            setState(() => _sortMode = SortMode.values[index]);
            _closeFilter();
          },
        );
    }
  }

  Widget _buildTitlesGrid(List<Sourced<PlexLibraryItem>> results) {
    if (widget.items.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(32.du(context)),
        child: const AppText('Nothing in this library yet.'),
      );
    }
    if (results.isEmpty) {
      return _buildEmptyResultsState();
    }
    return _fadingGrid(
      controller: _gridScrollController,
      grid: GridView.builder(
        controller: _gridScrollController,
        padding: EdgeInsets.only(bottom: 48.du(context)),
        clipBehavior: Clip.none,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridColumns,
          mainAxisSpacing: 24.du(context),
          crossAxisSpacing: 24.du(context),
          mainAxisExtent: _posterCardHeight.du(context),
        ),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final item = results[index];
          return PosterCard(
            key: ValueKey('${item.server.machineIdentifier}:${item.value.ratingKey}'),
            imageUrl: PlexImageUrl.of(item.server, item.value.thumb),
            title: item.value.title,
            autofocus: index == 0,
            staggerDelayMs: (index % _gridColumns) * 120,
            onClick: () => widget.onSelectItem(item),
          );
        },
      ),
    );
  }

  /// Screen 23 — inline, not a takeover: the rail, header and filter row
  /// all stay exactly where they were, and the copy names the specific
  /// filters responsible with real counts rather than a generic "no
  /// results" ("Name the cause, not the symptom" — DESIGN.md rule 10).
  /// Each cause gets its own "Drop the X" action; "Clear all" only when
  /// two or more are actually stacked.
  Widget _buildEmptyResultsState() {
    final causes =
        <
          (
            String headlineFragment,
            String dropLabel,
            String factLabel,
            VoidCallback onDrop,
          )
        >[
          if (_genreFilter != null)
            (
              '${formatGenreLabel(_genreFilter!).toLowerCase()} titles',
              'Drop the genre',
              '${applyLibraryFilters(items: _bareItems, query: '', sortMode: SortMode.title, genre: _genreFilter).length} ${formatGenreLabel(_genreFilter!).toLowerCase()} titles',
              () => setState(() => _genreFilter = null),
            ),
          if (_decadeFilter != null)
            (
              'titles from the ${_decadeFilter}s',
              'Drop the decade',
              '${applyLibraryFilters(items: _bareItems, query: '', sortMode: SortMode.title, decade: _decadeFilter).length} titles from the ${_decadeFilter}s',
              () => setState(() => _decadeFilter = null),
            ),
          if (_dateAddedFilter != null)
            (
              'titles added ${_dateAddedFilter!.label.toLowerCase()}',
              'Drop "Added"',
              '${applyLibraryFilters(items: _bareItems, query: '', sortMode: SortMode.title, dateAddedBucket: _dateAddedFilter).length} titles added ${_dateAddedFilter!.label.toLowerCase()}',
              () => setState(() => _dateAddedFilter = null),
            ),
        ];
    final searchActive = _searchQuery.trim().isNotEmpty;

    final String headline;
    final String? factSentence;
    if (causes.isEmpty && searchActive) {
      headline = 'Nothing matches "${_searchQuery.trim()}"';
      factSentence = null;
    } else if (causes.isEmpty) {
      headline = 'Nothing matches these filters';
      factSentence = null;
    } else {
      headline =
          'No ${causes.map((c) => c.$1).join(' + ')} on ${widget.selectedSectionGroup.title}';
      factSentence = causes.length > 1
          ? '${widget.selectedSectionGroup.title} has ${causes.map((c) => c.$3).join(' and ')}. Together they leave nothing.'
          : null;
    }

    return Padding(
      padding: EdgeInsets.only(top: 24.du(context), bottom: 48.du(context)),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 660.du(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                PhosphorIconsRegular.funnel,
                size: 64,
                tint: AppColors.lineStrong,
              ),
              SizedBox(height: 24.du(context)),
              AppText(
                headline,
                style: AppTypography.title2,
                textAlign: TextAlign.center,
              ),
              if (factSentence != null) ...[
                SizedBox(height: 12.du(context)),
                AppText(
                  factSentence,
                  color: AppColors.ink3,
                  textAlign: TextAlign.center,
                ),
              ],
              if (causes.isNotEmpty || searchActive) ...[
                SizedBox(height: 24.du(context)),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16.du(context),
                  runSpacing: 12.du(context),
                  children: [
                    for (final cause in causes)
                      AppOutlinedButton(
                        onClick: cause.$4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(PhosphorIconsRegular.x, size: 20),
                            SizedBox(width: AppSpacing.sm.du(context)),
                            AppText(cause.$2),
                          ],
                        ),
                      ),
                    if (searchActive)
                      AppOutlinedButton(
                        onClick: () => setState(() => _searchQuery = ''),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(PhosphorIconsRegular.x, size: 20),
                            SizedBox(width: AppSpacing.sm.du(context)),
                            const AppText('Clear search'),
                          ],
                        ),
                      ),
                    if (causes.length + (searchActive ? 1 : 0) > 1)
                      AppOutlinedButton(
                        onClick: () => setState(() {
                          _genreFilter = null;
                          _decadeFilter = null;
                          _dateAddedFilter = null;
                          _searchQuery = '';
                        }),
                        child: const AppText('Clear all'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionsGrid(List<Sourced<PlexCollection>>? results) {
    if (results == null) {
      return const LoadingScreen();
    }
    if (results.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(32.du(context)),
        child: const AppText('No collections found'),
      );
    }
    return _fadingGrid(
      controller: _collectionsScrollController,
      grid: GridView.builder(
        controller: _collectionsScrollController,
        padding: EdgeInsets.only(bottom: 48.du(context)),
        clipBehavior: Clip.none,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridColumns,
          mainAxisSpacing: 24.du(context),
          crossAxisSpacing: 24.du(context),
          mainAxisExtent: _posterCardHeight.du(context),
        ),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final collection = results[index];
          final childCount = collection.value.childCount;
          return PosterCard(
            key: ValueKey('${collection.server.machineIdentifier}:${collection.value.ratingKey}'),
            imageUrl: PlexImageUrl.of(collection.server, collection.value.thumb),
            title: collection.value.title,
            subtitle: childCount != null
                ? '$childCount title${childCount == 1 ? '' : 's'}'
                : null,
            autofocus: index == 0,
            onClick: () => widget.onSelectCollection(collection),
          );
        },
      ),
    );
  }
}

RoundedRectangleBorder _segmentShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
    );
final _segmentColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink3,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
final _segmentBorder = SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// The Titles/Collections view switch (screens 17-19: "a view switch...
/// two options in one segmented control at the head of the filter bar, not
/// a tab among four").
class _ModeSwitch extends StatelessWidget {
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onSelect;
  final FocusNode titlesFocusNode;
  final FocusNode collectionsFocusNode;

  const _ModeSwitch({
    required this.mode,
    required this.onSelect,
    required this.titlesFocusNode,
    required this.collectionsFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(5.du(context)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentButton(
            context,
            'Titles',
            mode == _ViewMode.titles,
            titlesFocusNode,
            () => onSelect(_ViewMode.titles),
          ),
          SizedBox(width: 6.du(context)),
          _segmentButton(
            context,
            'Collections',
            mode == _ViewMode.collections,
            collectionsFocusNode,
            () => onSelect(_ViewMode.collections),
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(
    BuildContext context,
    String label,
    bool selected,
    FocusNode focusNode,
    VoidCallback onClick,
  ) {
    return SizedBox(
      height: 48.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _segmentShape(context),
        colors: _segmentColors,
        border: _segmentBorder,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22.du(context)),
          child: AppText(label),
        ),
      ),
    );
  }
}

RoundedRectangleBorder _filterChipShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
final _filterChipColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.accent900,
  selectedContent: AppColors.accent300,
);
final _filterChipBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// One dropdown-trigger chip in the filter row (Genre/Decade/Added/Sort).
/// Visual "open" state is just this chip having real D-pad focus while its
/// panel happens to be showing — [FocusableSurface]'s existing focused
/// treatment already matches the mockup's highlighted-chip look, so `open`
/// only changes the caret direction and whether the value is shown inline.
class _FilterChip extends StatelessWidget {
  final String label;
  final String? valueLabel;
  final bool open;
  final bool alwaysShowValue;
  final FocusNode focusNode;
  final VoidCallback onClick;

  const _FilterChip({
    super.key,
    required this.label,
    this.valueLabel,
    required this.open,
    this.alwaysShowValue = false,
    required this.focusNode,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final applied = valueLabel != null;
    final text = applied
        ? (open || alwaysShowValue ? '$label · $valueLabel' : valueLabel!)
        : label;
    return SizedBox(
      height: 58.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: applied && !alwaysShowValue,
        focusNode: focusNode,
        shape: _filterChipShape(context),
        colors: _filterChipColors,
        border: _filterChipBorder,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.du(context)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(text),
              SizedBox(width: 12.du(context)),
              AppIcon(
                open
                    ? PhosphorIconsRegular.caretUp
                    : PhosphorIconsRegular.caretDown,
                size: 18,
                tint: AppColors.ink4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearAllChip extends StatelessWidget {
  final FocusNode focusNode;
  final VoidCallback onClick;

  const _ClearAllChip({required this.focusNode, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58.du(context),
      child: FocusableSurface(
        onClick: onClick,
        focusNode: focusNode,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        colors: SurfaceColors(
          container: AppColors.transparent,
          content: AppColors.ink2,
          focusedContainer: AppColors.surfaceRaised,
          focusedContent: AppColors.ink,
          selectedContainer: AppColors.transparent,
          selectedContent: AppColors.ink2,
        ),
        border: SurfaceBorder(
          idle: SurfaceBorderSide.solid(AppColors.lineStrong),
          focused: SurfaceBorderSide.solid(AppColors.accent),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.du(context)),
          child: const AppText('Clear all'),
        ),
      ),
    );
  }
}
