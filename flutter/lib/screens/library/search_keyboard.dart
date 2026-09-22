import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

enum SearchKeyAction { char, delete, clear }

class SearchKey {
  final String label;
  final String? insert;
  final SearchKeyAction action;
  final int span;

  const SearchKey({required this.label, this.insert, this.action = SearchKeyAction.char, this.span = 1});
}

/// A-Z, 0-9 chunked 6 per row, then a final row of SPACE/DELETE/CLEAR
/// (each spanning 2 of the 6 columns). Ports SEARCH_KEY_ROWS.
final List<List<SearchKey>> searchKeyRows = () {
  final chars = [
    for (var i = 0; i < 26; i++) String.fromCharCode(65 + i),
    for (var i = 0; i < 10; i++) '$i',
  ];
  final rows = <List<SearchKey>>[];
  for (var i = 0; i < chars.length; i += 6) {
    rows.add(chars.skip(i).take(6).map((c) => SearchKey(label: c, insert: c)).toList());
  }
  rows.add([
    const SearchKey(label: 'SPACE', insert: ' ', span: 2),
    const SearchKey(label: '⌫ DELETE', action: SearchKeyAction.delete, span: 2),
    const SearchKey(label: 'CLEAR', action: SearchKeyAction.clear, span: 2),
  ]);
  return rows;
}();

/// Span-expanded grid (each key repeated once per column it occupies) —
/// used for column-index neighbor lookup. Ports SEARCH_KEY_GRID.
final List<List<SearchKey>> searchKeyGrid = searchKeyRows.map((row) {
  final expanded = <SearchKey>[];
  for (final key in row) {
    for (var i = 0; i < key.span; i++) {
      expanded.add(key);
    }
  }
  return expanded;
}).toList();

const _keyHeight = 52.0;
const _keyGap = AppSpacing.xs;
final _keyShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.radiusSm));
final _keyColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
// noSpine — a key is a small, icon-like glyph target (DESIGN.md #3), not a
// card; a leading spine would read as a sliver on something this square.
const _keyBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// Ports ui/library/LibraryScreen.kt's `SearchKeyboard` — a hand-wired
/// D-pad grid (small, tightly-packed keys where span-2 keys make default
/// 2D directional traversal unreliable, so every interior neighbor gets an
/// explicit requestFocus() rather than relying on Flutter's default
/// traversal). Up/down are trapped (Cancel) at the top/bottom rows since
/// there's nothing meaningful above/below to escape to from mid-keyboard;
/// left/right at the row edges are deliberately left unhandled (falls
/// through to default traversal), matching the Kotlin source only setting
/// `left`/`right` conditionally.
class SearchKeyboard extends StatefulWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool autofocus;
  // Lets a caller (e.g. right after switching to the Search tab) explicitly
  // request focus onto the first key. autofocus alone isn't reliable here:
  // whatever had focus before this widget mounted (the Search tab button
  // itself, in practice) still holds it in the enclosing scope, and
  // Flutter's autofocus declines to steal focus from an already-focused
  // scope — see the matching fix in player_screen.dart for the same issue.
  final FocusNode? firstKeyFocusNode;

  const SearchKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    this.autofocus = false,
    this.firstKeyFocusNode,
  });

  @override
  State<SearchKeyboard> createState() => _SearchKeyboardState();
}

class _SearchKeyboardState extends State<SearchKeyboard> {
  late final Map<SearchKey, FocusNode> _focusNodes = {
    for (var r = 0; r < searchKeyRows.length; r++)
      for (var c = 0; c < searchKeyRows[r].length; c++)
        searchKeyRows[r][c]: (r == 0 && c == 0 && widget.firstKeyFocusNode != null)
            ? widget.firstKeyFocusNode!
            : FocusNode(debugLabel: 'search-key-${searchKeyRows[r][c].label}'),
  };

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      if (node != widget.firstKeyFocusNode) node.dispose();
    }
    super.dispose();
  }

  void _handleClick(SearchKey key) {
    switch (key.action) {
      case SearchKeyAction.char:
        final insert = key.insert;
        if (insert != null) widget.onChar(insert);
      case SearchKeyAction.delete:
        widget.onBackspace();
      case SearchKeyAction.clear:
        widget.onClear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var rowIndex = 0; rowIndex < searchKeyRows.length; rowIndex++) ...[
          if (rowIndex > 0) const SizedBox(height: _keyGap),
          _buildRow(rowIndex),
        ],
      ],
    );
  }

  Widget _buildRow(int rowIndex) {
    final row = searchKeyRows[rowIndex];
    final children = <Widget>[];
    var col = 0;
    for (final key in row) {
      if (children.isNotEmpty) children.add(const SizedBox(width: _keyGap));
      final colStart = col;
      final colEnd = col + key.span - 1;
      col += key.span;

      final up = rowIndex > 0 ? _focusNodes[searchKeyGrid[rowIndex - 1][colStart]] : null;
      final down = rowIndex < searchKeyRows.length - 1 ? _focusNodes[searchKeyGrid[rowIndex + 1][colStart]] : null;
      final left = colStart > 0 ? _focusNodes[searchKeyGrid[rowIndex][colStart - 1]] : null;
      final right = colEnd < 5 ? _focusNodes[searchKeyGrid[rowIndex][colEnd + 1]] : null;

      children.add(
        Expanded(
          flex: key.span,
          child: _SearchKeyButton(
            searchKey: key,
            focusNode: _focusNodes[key]!,
            autofocus: widget.autofocus && rowIndex == 0 && colStart == 0,
            trapUp: rowIndex == 0,
            trapDown: rowIndex == searchKeyRows.length - 1,
            upNeighbor: up,
            downNeighbor: down,
            leftNeighbor: left,
            rightNeighbor: right,
            onClick: () => _handleClick(key),
            onLongClick: key.action == SearchKeyAction.delete ? widget.onClear : null,
          ),
        ),
      );
    }
    return Row(children: children);
  }
}

class _SearchKeyButton extends StatelessWidget {
  final SearchKey searchKey;
  final FocusNode focusNode;
  final bool autofocus;
  final bool trapUp;
  final bool trapDown;
  final FocusNode? upNeighbor;
  final FocusNode? downNeighbor;
  final FocusNode? leftNeighbor;
  final FocusNode? rightNeighbor;
  final VoidCallback onClick;
  final VoidCallback? onLongClick;

  const _SearchKeyButton({
    required this.searchKey,
    required this.focusNode,
    this.autofocus = false,
    required this.trapUp,
    required this.trapDown,
    this.upNeighbor,
    this.downNeighbor,
    this.leftNeighbor,
    this.rightNeighbor,
    required this.onClick,
    this.onLongClick,
  });

  KeyEventResult _handleArrowKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (upNeighbor != null) {
        upNeighbor!.requestFocus();
        return KeyEventResult.handled;
      }
      return trapUp ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (downNeighbor != null) {
        downNeighbor!.requestFocus();
        return KeyEventResult.handled;
      }
      return trapDown ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft && leftNeighbor != null) {
      leftNeighbor!.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight && rightNeighbor != null) {
      rightNeighbor!.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _keyHeight,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleArrowKeys,
        child: FocusableSurface(
          onClick: onClick,
          onLongClick: onLongClick,
          focusNode: focusNode,
          autofocus: autofocus,
          shape: _keyShape,
          colors: _keyColors,
          border: _keyBorder,
          child: AppText(
            searchKey.label,
            textAlign: TextAlign.center,
            style: AppTypography.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
