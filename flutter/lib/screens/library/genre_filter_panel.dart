import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/neon_scrollbar.dart';
import 'library_filters.dart';

final RegExp _missingSpaceAfterAmpersand = RegExp(r'&(?=\S)');

String formatGenreLabel(String genre) => genre.replaceAllMapped(_missingSpaceAfterAmpersand, (_) => '& ');

class AppliedFilterChip extends StatelessWidget {
  final String label;

  const AppliedFilterChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(50)),
      child: AppText(label, color: AppColors.inkOnArt),
    );
  }
}

class MenuSectionHeader extends StatelessWidget {
  final String label;

  const MenuSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: AppText(
        label.toUpperCase(),
        style: AppTypography.micro,
      ),
    );
  }
}

final _menuShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.radiusMd));
final _menuRowColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surface,
  selectedContent: AppColors.ink,
);
const _menuRowBorder = SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent));

class MenuOptionRow extends StatelessWidget {
  final String label;
  final bool applied;
  final bool dimmed;
  final VoidCallback onClick;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  const MenuOptionRow({
    super.key,
    required this.label,
    required this.applied,
    this.dimmed = false,
    required this.onClick,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = dimmed
        ? SurfaceColors(
            container: _menuRowColors.container,
            content: _menuRowColors.content.withValues(alpha: 0.5),
            focusedContainer: _menuRowColors.focusedContainer,
            focusedContent: _menuRowColors.focusedContent.withValues(alpha: 0.5),
            selectedContainer: _menuRowColors.selectedContainer,
            selectedContent: _menuRowColors.selectedContent.withValues(alpha: 0.5),
          )
        : _menuRowColors;

    return SizedBox(
      height: 46,
      child: FocusableSurface(
        onClick: onClick,
        selected: applied,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        shape: _menuShape,
        colors: colors,
        border: _menuRowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (applied) ...[const AppText('✓'), const SizedBox(width: 8)],
              Flexible(child: AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ports ui/library/LibraryScreen.kt's `GenreFilterPanel` — genre/decade/
/// date-added filter rows, each dimmed if selecting it alongside the
/// currently-active filters would produce zero results. Down is trapped
/// at the last row (checklist-adjacent: without it, an unhandled Down
/// could let focus escape somewhere unintended below); Up at the first
/// row hands off to [aboveFocusNode] (the Genre tab or Clear-all).
/// Right isn't given an explicit redirect to the results grid — Flutter's
/// default directional traversal already finds the nearest focusable
/// widget to the right (the results grid sits directly beside this
/// panel), same as relied on elsewhere in this conversion.
class GenreFilterPanel extends StatefulWidget {
  final List<PlexLibraryItem> items;
  final List<String> availableGenres;
  final List<int> availableDecades;
  final String? genreFilter;
  final int? decadeFilter;
  final DateAddedBucket? dateAddedFilter;
  final FocusNode aboveFocusNode;
  final ValueChanged<String> onGenreSelect;
  final ValueChanged<int> onDecadeSelect;
  final ValueChanged<DateAddedBucket> onDateAddedSelect;
  final VoidCallback onClearAll;

  const GenreFilterPanel({
    super.key,
    required this.items,
    required this.availableGenres,
    required this.availableDecades,
    this.genreFilter,
    this.decadeFilter,
    this.dateAddedFilter,
    required this.aboveFocusNode,
    required this.onGenreSelect,
    required this.onDecadeSelect,
    required this.onDateAddedSelect,
    required this.onClearAll,
  });

  @override
  State<GenreFilterPanel> createState() => _GenreFilterPanelState();
}

class _GenreFilterPanelState extends State<GenreFilterPanel> {
  final _scrollController = ScrollController();
  int _highlightedIndex = 0;
  // Keyed by stable row identity, not list position — "Clear all" only
  // exists once some filter is applied, so every row after it used to shift
  // by one position whenever it appeared/disappeared. With a plain
  // List<FocusNode> indexed by position, that shift handed each row a
  // FocusNode object that used to belong to a *different* row (e.g. "Clear
  // all" would inherit whatever node "Action" — the row that used to sit at
  // index 0 — had, including that node's real, possibly-still-true
  // hasFocus), which is exactly what made two rows appear focused at once.
  // Keying by identity means a row's node follows it, never another row's.
  final _focusNodesById = <String, FocusNode>{};

  List<String> _computeRowIds() {
    final anyApplied = widget.genreFilter != null || widget.decadeFilter != null || widget.dateAddedFilter != null;
    return [
      if (anyApplied) 'clear-all',
      for (final genre in widget.availableGenres) 'genre:$genre',
      for (final decade in widget.availableDecades) 'decade:$decade',
      for (final bucket in DateAddedBucket.values) 'dateAdded:${bucket.name}',
    ];
  }

  FocusNode _nodeFor(String id) => _focusNodesById.putIfAbsent(id, () => FocusNode(debugLabel: 'genre-filter-$id'));

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant GenreFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  void _syncFocusNodes() {
    final ids = _computeRowIds().toSet();
    _focusNodesById.removeWhere((id, node) {
      final stale = !ids.contains(id);
      if (stale) node.dispose();
      return stale;
    });
    if (_highlightedIndex >= ids.length) _highlightedIndex = ids.isNotEmpty ? ids.length - 1 : 0;
  }

  @override
  void dispose() {
    for (final node in _focusNodesById.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handlePanelKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _highlightedIndex == _computeRowIds().length - 1) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _highlightedIndex == 0) {
      widget.aboveFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final anyApplied = widget.genreFilter != null || widget.decadeFilter != null || widget.dateAddedFilter != null;
    var rowIndex = 0;
    ValueChanged<bool> onFocus(int index) => (focused) {
          if (focused) setState(() => _highlightedIndex = index);
        };

    final rows = <Widget>[];
    if (anyApplied) {
      final index = rowIndex++;
      rows.add(MenuOptionRow(
        key: const ValueKey('clear-all'),
        label: 'Clear all',
        applied: false,
        onClick: widget.onClearAll,
        focusNode: _nodeFor('clear-all'),
        onFocusChange: onFocus(index),
      ));
    }
    if (widget.availableGenres.isNotEmpty) {
      rows.add(const MenuSectionHeader(label: 'Genre'));
      for (final genre in widget.availableGenres) {
        final index = rowIndex++;
        final dimmed = applyLibraryFilters(
          items: widget.items,
          query: '',
          sortMode: SortMode.title,
          genre: genre,
          decade: widget.decadeFilter,
          dateAddedBucket: widget.dateAddedFilter,
        ).isEmpty;
        rows.add(MenuOptionRow(
          key: ValueKey('genre:$genre'),
          label: formatGenreLabel(genre),
          applied: genre == widget.genreFilter,
          dimmed: dimmed,
          onClick: () => widget.onGenreSelect(genre),
          focusNode: _nodeFor('genre:$genre'),
          onFocusChange: onFocus(index),
        ));
      }
    }
    if (widget.availableDecades.isNotEmpty) {
      rows.add(const MenuSectionHeader(label: 'Release Date'));
      for (final decade in widget.availableDecades) {
        final index = rowIndex++;
        final dimmed = applyLibraryFilters(
          items: widget.items,
          query: '',
          sortMode: SortMode.title,
          genre: widget.genreFilter,
          decade: decade,
          dateAddedBucket: widget.dateAddedFilter,
        ).isEmpty;
        rows.add(MenuOptionRow(
          key: ValueKey('decade:$decade'),
          label: '${decade}s',
          applied: decade == widget.decadeFilter,
          dimmed: dimmed,
          onClick: () => widget.onDecadeSelect(decade),
          focusNode: _nodeFor('decade:$decade'),
          onFocusChange: onFocus(index),
        ));
      }
    }
    rows.add(const MenuSectionHeader(label: 'Date Added'));
    for (final bucket in DateAddedBucket.values) {
      final index = rowIndex++;
      final dimmed = applyLibraryFilters(
        items: widget.items,
        query: '',
        sortMode: SortMode.title,
        genre: widget.genreFilter,
        decade: widget.decadeFilter,
        dateAddedBucket: bucket,
      ).isEmpty;
      rows.add(MenuOptionRow(
        key: ValueKey('dateAdded:${bucket.name}'),
        label: bucket.label,
        applied: bucket == widget.dateAddedFilter,
        dimmed: dimmed,
        onClick: () => widget.onDateAddedSelect(bucket),
        focusNode: _nodeFor('dateAdded:${bucket.name}'),
        onFocusChange: onFocus(index),
      ));
    }

    return ColoredBox(
      color: AppColors.surface,
      // The scroll view below can't clip at its own tight edge (that cuts
      // the focused-row glow off — see its comment), but leaving the panel
      // with no clip at all let scrolled rows paint straight over the tab
      // bar above once they scrolled past the top. Clipping here instead —
      // at the panel's own outer edge, outside the 24px padding — keeps
      // scrolled content contained to the panel while still leaving that
      // padding as slack for the glow to bleed into.
      child: ClipRect(
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handlePanelKeyEvent,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    clipBehavior: Clip.none,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final row in rows) ...[row, const SizedBox(height: 2)],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                NeonScrollbar(controller: _scrollController),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
