import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelay/screens/library/poster_card.dart' show posterRowPeekExtent;
import 'package:reelay/theme/scale.dart';

import 'journey.dart';

/// A poster grid's scroll (PosterGrid, ensureRowVisible), checked with the
/// remote: whole, unclipped focus; Down goes to the card straight below;
/// while there's more grid, part of the next row peeks in; Up comes back a
/// row at a time, never yanking; a held Down keeps up, then the grid sits
/// still.
extension GridChecks on Journey {
  /// The vertical grid the focused card is in, if it's in one.
  ScrollableState? get focusedGrid {
    final context = focus?.context;
    if (context == null) return null;
    return Scrollable.maybeOf(context, axis: Axis.vertical);
  }

  Rect _boxOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect _shown(ScrollableState grid) {
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    return _boxOf(grid.context).intersect(screen);
  }

  void _expectWhole(ScrollableState grid, String where) {
    final rect = focusedRect()!;
    final shown = _shown(grid);
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    // With the 1.03 focus scale about its centre. A grid doesn't clip its
    // sides (Clip.none, so the scale spills over its edge): sideways the
    // card only has to be on screen; top and bottom, inside the grid.
    final scaled = rect.inflate(rect.height * 0.015);
    expect(scaled.top >= shown.top - 1 && scaled.bottom <= shown.bottom + 1 && scaled.left >= screen.left && scaled.right <= screen.right,
        isTrue,
        reason: why('$where: the focused card (scaled) should be whole — $scaled, grid shows $shown'));
    // Scrolled, a grid fades its top edge (posterRowPeekExtent): the focused
    // card sits below the fade, never in it.
    if (grid.position.pixels > 1) {
      final fade = posterRowPeekExtent.du(grid.context);
      expect(rect.top, greaterThanOrEqualTo(shown.top + fade - 2),
          reason: why('$where: the focused card is under the grid\'s top fade — its top at ${rect.top.toStringAsFixed(0)}, '
              'the fade ends at ${(shown.top + fade).toStringAsFixed(0)}'));
    }
  }

  /// Any card of the grid other than the focused one starting below it —
  /// the next row — showing at the grid's bottom.
  bool _nextRowPeeks(ScrollableState grid, Rect focused) {
    final shown = _shown(grid);
    for (final node in FocusManager.instance.rootScope.descendants) {
      final context = node.context;
      if (context == null || !node.canRequestFocus || node.skipTraversal) continue;
      if (Scrollable.maybeOf(context, axis: Axis.vertical) != grid) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = _boxOf(context);
      if (rect.top >= focused.bottom - 1 && rect.top < shown.bottom - 1) return true;
    }
    return false;
  }

  /// Walks the focused card's grid down its first column to the end, back
  /// up, then holds Down across it. Leaves focus where it started.
  Future<int> walkGrid(String name) async {
    final grid = focusedGrid;
    expect(grid, isNotNull, reason: why('$name: focus should be in a grid'));
    final position = grid!.position;
    _expectWhole(grid, '$name, first card');
    final column = focusedRect()!.left;
    final rows = <double>[position.pixels + focusedRect()!.top]; // each row's place in the content

    while (rows.length < 80) {
      final before = focus;
      final from = focusedRect()!;
      await down();
      await wait(const Duration(milliseconds: 200));
      if (focus == before || focusedGrid != grid) {
        if (focusedGrid != grid) await up();
        break;
      }
      final here = '$name, row ${rows.length + 1}';
      final rect = focusedRect()!;
      expect((rect.left - column).abs(), lessThan(2), reason: why('$here: Down goes straight down, same column (from $from to $rect)'));
      rows.add(position.pixels + rect.top);
      _expectWhole(grid, here);
      if (position.extentAfter > rect.height) {
        expect(_nextRowPeeks(grid, rect), isTrue, reason: why('$here: there is more grid, so the next row should peek in'));
      }
    }

    final rowStep = rows.length > 1 ? (rows[1] - rows[0]) : focusedRect()!.height;
    for (var i = rows.length - 1; i > 0; i--) {
      final from = position.pixels;
      await up();
      await wait(const Duration(milliseconds: 200));
      final here = '$name, back up to row $i';
      expect(position.pixels + focusedRect()!.top, closeTo(rows[i - 1], 2), reason: why('$here: Up goes back one row'));
      expect((from - position.pixels).abs(), lessThanOrEqualTo(rowStep * 1.3),
          reason: why('$here: back up reveals a row, it doesn\'t yank the grid (${from - position.pixels} px)'));
      _expectWhole(grid, here);
    }

    if (rows.length >= 3) {
      final repeats = rows.length - 2;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < repeats; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        // Frames at the TV's 60 Hz between repeats: one frame per repeat
        // left a restarted scroll animation forever at its first tick.
        for (var f = 0; f < 3; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await wait(const Duration(milliseconds: 800));
      steps.add('Hold Down ×${repeats + 1} → ${describeFocus()}');
      expect(position.pixels + focusedRect()!.top, closeTo(rows.last, 2), reason: why('$name: holding Down, focus keeps up — a row per repeat'));
      _expectWhole(grid, '$name, after holding Down');
      final settled = position.pixels;
      await wait(const Duration(seconds: 1));
      expect(position.pixels, settled, reason: why('$name: once the key is let go the grid sits still'));
      await up(rows.length - 1);
    }
    return rows.length;
  }
}
