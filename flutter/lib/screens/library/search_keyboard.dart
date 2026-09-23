import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

enum SearchKeyAction { char, delete, clear, toggleSymbols }

class SearchKey {
  final String label;
  final String? insert;
  final SearchKeyAction action;
  final int span;

  const SearchKey({
    required this.label,
    this.insert,
    this.action = SearchKeyAction.char,
    this.span = 1,
  });
}

const _columns = 6;

List<SearchKey> _chars(String chars) => [
  for (final c in chars.split('')) SearchKey(label: c, insert: c),
];

/// Screen 05's keyboard: six columns — A-Z, a "123" switch and backspace,
/// then space and clear across the bottom. The symbols page has exactly
/// the same shape, so switching never moves focus off the key under it.
List<List<SearchKey>> searchKeyRows({required bool symbols}) {
  final glyphs = symbols
      ? _chars("1234567890&-':!?.,()#+/\"%@")
      : _chars('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  return [
    for (var i = 0; i < 24; i += _columns) glyphs.sublist(i, i + _columns),
    [
      ...glyphs.sublist(24, 26),
      SearchKey(
        label: symbols ? 'ABC' : '123',
        action: SearchKeyAction.toggleSymbols,
        span: 2,
      ),
      const SearchKey(label: 'delete', action: SearchKeyAction.delete, span: 2),
    ],
    const [
      SearchKey(label: 'space', insert: ' ', span: 3),
      SearchKey(label: 'clear', action: SearchKeyAction.clear, span: 3),
    ],
  ];
}

// Smaller than screen 05's 76 / 10 — the full-size keyboard dominated the
// screen; the column it fills narrows with it (see search_screen.dart).
const _keyHeight = 60.0;
const _keyGap = 8.0;
RoundedRectangleBorder _keyShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
    );
SurfaceColors get _keyColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
// noSpine — a key is a small square glyph target (DESIGN.md #3); a leading
// spine would read as a sliver on something this size.
SurfaceBorder get _keyBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
  noSpine: true,
);

/// A hand-wired D-pad grid: spans make default 2D traversal unreliable, so
/// every neighbour is explicit. Focus nodes belong to grid positions, not
/// to keys, so the symbols switch keeps focus exactly where it was. Up at
/// the top row and down at the bottom row are trapped (the keyboard keeps
/// focus — results never steal it); left at the leading edge falls through
/// to the rail, right at the trailing edge is trapped.
class SearchKeyboard extends StatefulWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final FocusNode? firstKeyFocusNode;

  const SearchKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    this.firstKeyFocusNode,
  });

  @override
  State<SearchKeyboard> createState() => _SearchKeyboardState();
}

class _SearchKeyboardState extends State<SearchKeyboard> {
  bool _symbols = false;

  /// One node per (row, first column) cell.
  late final Map<(int, int), FocusNode> _nodes = {
    for (final (r, row) in searchKeyRows(symbols: false).indexed)
      for (final c in _starts(row))
        (r, c): (r == 0 && c == 0 && widget.firstKeyFocusNode != null)
            ? widget.firstKeyFocusNode!
            : FocusNode(debugLabel: 'search-key-$r-$c'),
  };

  static List<int> _starts(List<SearchKey> row) {
    final starts = <int>[];
    var c = 0;
    for (final k in row) {
      starts.add(c);
      c += k.span;
    }
    return starts;
  }

  /// The node whose key covers [col] in [row].
  FocusNode _nodeAt(int row, int col) {
    final keys = searchKeyRows(symbols: _symbols)[row];
    var start = 0;
    for (final k in keys) {
      if (col < start + k.span) return _nodes[(row, start)]!;
      start += k.span;
    }
    return _nodes[(row, _starts(keys).last)]!;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      if (node != widget.firstKeyFocusNode) node.dispose();
    }
    super.dispose();
  }

  void _press(SearchKey key) {
    switch (key.action) {
      case SearchKeyAction.char:
        if (key.insert != null) widget.onChar(key.insert!);
      case SearchKeyAction.delete:
        widget.onBackspace();
      case SearchKeyAction.clear:
        widget.onClear();
      case SearchKeyAction.toggleSymbols:
        setState(() => _symbols = !_symbols);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = searchKeyRows(symbols: _symbols);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) SizedBox(height: _keyGap.du(context)),
          Row(
            children: [
              for (final (i, key) in row.indexed) ...[
                if (i > 0) SizedBox(width: _keyGap.du(context)),
                Expanded(
                  flex: key.span,
                  child: _buildKey(context, rows, r, _starts(row)[i], key),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildKey(
    BuildContext context,
    List<List<SearchKey>> rows,
    int r,
    int c,
    SearchKey key,
  ) {
    final last = rows.length - 1;
    final end = c + key.span - 1;
    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent)
        return KeyEventResult.ignored;
      final k = event.logicalKey;
      FocusNode? target;
      if (k == LogicalKeyboardKey.arrowUp) {
        if (r == 0) return KeyEventResult.handled;
        target = _nodeAt(r - 1, c);
      } else if (k == LogicalKeyboardKey.arrowDown) {
        if (r == last) return KeyEventResult.handled;
        target = _nodeAt(r + 1, c);
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        if (c == 0) return KeyEventResult.ignored;
        target = _nodeAt(r, c - 1);
      } else if (k == LogicalKeyboardKey.arrowRight) {
        // Off the right edge: on to the results beside the keyboard when
        // there are any; with none, stay put rather than lose focus.
        if (end >= _columns - 1) {
          node.focusInDirection(TraversalDirection.right);
          return KeyEventResult.handled;
        }
        target = _nodeAt(r, end + 1);
      } else {
        return KeyEventResult.ignored;
      }
      target.requestFocus();
      return KeyEventResult.handled;
    }

    final isWord = key.label.length > 1;
    final Widget label = key.action == SearchKeyAction.delete
        ? const AppIcon(PhosphorIconsRegular.backspace, size: 24)
        : AppText(
            key.label,
            textAlign: TextAlign.center,
            style: isWord
                ? AppTypography.label
                : AppTypography.rowLabel.copyWith(fontWeight: FontWeight.w400),
            color: isWord ? AppColors.ink3 : null,
            maxLines: 1,
          );
    return SizedBox(
      height: _keyHeight.du(context),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: onKey,
        child: FocusableSurface(
          key: ValueKey('key-$r-$c'),
          onClick: () => _press(key),
          onLongClick: key.action == SearchKeyAction.delete
              ? widget.onClear
              : null,
          focusNode: _nodes[(r, c)],
          shape: _keyShape(context),
          colors: _keyColors,
          border: _keyBorder,
          child: Semantics(
            label: key.action == SearchKeyAction.delete ? 'delete' : null,
            child: label,
          ),
        ),
      ),
    );
  }
}
