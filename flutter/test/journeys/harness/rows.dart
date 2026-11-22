import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reelay/theme/scale.dart';
import 'package:reelay/theme/tokens.dart';

import 'journey.dart';

/// DESIGN.md's row rules, checked on a real row with the remote:
///
/// - the focused card is whole on screen, its focus scale and border never
///   clipped by the row's track ("A row's track is card height +
///   rowHeadroom … never clipped");
/// - the row holds still while focus moves between cards it already shows
///   whole, and scrolls only when focus moves to a card past an edge — just
///   far enough to show that card whole, at the edge (the safe margin);
/// - the last card stops flush with the row's end (RowEndStop);
/// - a held direction lands where the presses say, and the row then sits
///   still.
/// A row's scroll (AppMotion.rowScroll) starts a frame after the press;
/// measure once it's done.
const _settle = Duration(milliseconds: 150);

extension RowChecks on Journey {
  /// The horizontal row the focused card is in, if it's in one.
  ScrollableState? get focusedRow {
    final context = focus?.context;
    if (context == null) return null;
    return Scrollable.maybeOf(context, axis: Axis.horizontal);
  }

  Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The on-screen part of [row]: its viewport, cut to the screen.
  Rect _visible(ScrollableState row) {
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    return _rectOf(row.context).intersect(screen);
  }

  /// Which card is focused, by its place along the row's content — the
  /// same card at any scroll (its text can be an initial, its box moves).
  int _cardAt(ScrollableState row) => (focusedRect()!.left - _rectOf(row.context).left + row.position.pixels).round();

  /// The row's edges: its on-screen part less the safe margin each side —
  /// where its edge fade starts.
  ({double left, double right}) _edges(ScrollableState row) {
    final inset = AppSpacing.safeX.du(row.context);
    final visible = _visible(row);
    return (left: visible.left + inset, right: visible.right - inset);
  }

  /// After a press moved focus: if the card it landed on was already whole
  /// inside the row's edges, the row mustn't have moved; if not, it moved
  /// just far enough to bring that card to the edge (or to its own end).
  void _expectEdgeScroll(ScrollableState row, double pixelsBefore, String where) {
    final position = row.position;
    final rect = focusedRect()!;
    final moved = position.pixels - pixelsBefore;
    final wasLeft = rect.left + moved, wasRight = rect.right + moved;
    final edges = _edges(row);
    if (wasLeft >= edges.left - 1 && wasRight <= edges.right + 1) {
      expect(moved.abs(), lessThan(1),
          reason: why('$where: the card was already whole on screen, so the row should hold still (it moved ${moved.toStringAsFixed(0)} px)'));
      return;
    }
    final atAnEnd = position.pixels <= position.minScrollExtent + 1 || position.pixels >= position.maxScrollExtent - 1;
    final atRightEdge = (rect.right - edges.right).abs() <= 2;
    final atLeftEdge = (rect.left - edges.left).abs() <= 2;
    expect(atAnEnd || (wasRight > edges.right ? atRightEdge : atLeftEdge), isTrue,
        reason: why('$where: the card was past an edge, so the row moves just far enough to bring it to that edge — '
            'it\'s at $rect, edges ${edges.left.toStringAsFixed(0)}–${edges.right.toStringAsFixed(0)}'));
  }

  void _expectCardWhole(ScrollableState row, String where) {
    final rect = focusedRect()!;
    final visible = _visible(row);
    expect(rect.left >= visible.left - 1 && rect.right <= visible.right + 1, isTrue,
        reason: why('$where: the focused card should be whole on screen — $rect, row shows $visible'));
    // The focus signal scales the card 1.03 about its centre: its track
    // has to hold that, top and bottom.
    final scaled = rect.inflate(rect.height * 0.015);
    final track = _rectOf(row.context);
    expect(scaled.top >= track.top - 1 && scaled.bottom <= track.bottom + 1, isTrue,
        reason: why('$where: the focused card, scaled, is clipped by its row — $scaled in $track'));
  }

  /// Walks the focused card's row to its end, back to its start, then holds
  /// Right across it — checking DESIGN.md's row rules at every press.
  /// Leaves focus where it started. [name] is for the failure messages.
  Future<void> walkRow(String name) async {
    final row = focusedRow;
    expect(row, isNotNull, reason: why('$name: focus should be in a horizontal row'));
    final position = row!.position;
    // From the row's real start: Down into a row lands on whichever card
    // is nearest, not always its first.
    for (var i = 0; i < 60; i++) {
      final before = focus;
      await left();
      if (focusedRow != row) {
        await right(); // Left left the row (to the rail): come back
        break;
      }
      if (focus == before) break;
    }
    await wait(_settle);
    final cards = <int>[_cardAt(row)];
    _expectCardWhole(row, '$name, first card');

    // Right to the end.
    while (cards.length < 60) {
      final before = focus;
      final pixelsBefore = position.pixels;
      await right();
      await wait(_settle);
      if (focus == before || focusedRow != row) {
        if (focusedRow != row) await left(); // Right left the row: come back
        break;
      }
      cards.add(_cardAt(row));
      final here = '$name, card ${cards.length}';
      _expectCardWhole(row, here);
      _expectEdgeScroll(row, pixelsBefore, here);
    }
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent + 0.5),
        reason: why('$name: the last card stops flush, not past the end'));
    if (position.maxScrollExtent > 0) {
      expect(position.pixels, closeTo(position.maxScrollExtent, 1),
          reason: why('$name: at its last card the row is scrolled to its end'));
    }

    // Back to the start.
    for (var i = cards.length - 1; i > 0; i--) {
      final from = position.pixels;
      await left();
      await wait(_settle);
      final here = '$name, back to card $i';
      expect(_cardAt(row), closeTo(cards[i - 1], 2), reason: why('$here: Left goes back one card'));
      _expectCardWhole(row, here);
      _expectEdgeScroll(row, from, here);
    }
    expect(position.pixels, closeTo(0, 1), reason: why('$name: back at its first card, the row is home'));

    // Hold Right across it: focus keeps up, and the row settles once.
    if (cards.length >= 3) {
      final repeats = cards.length - 2; // the press, then repeats: to the last card
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 400)); // the platform's repeat delay
      for (var i = 0; i < repeats; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await wait(const Duration(milliseconds: 600));
      steps.add('Hold Right ×${repeats + 1} → ${describeFocus()}');
      expect(_cardAt(row), closeTo(cards.last, 2), reason: why('$name: holding Right, focus keeps up — one card per repeat'));
      _expectCardWhole(row, '$name, after holding Right');
      final settled = position.pixels;
      await wait(const Duration(seconds: 1));
      expect(position.pixels, settled, reason: why('$name: once the key is let go the row sits still'));
      await left(cards.length - 1);
    }
  }

  /// Walks every horizontal row on the screen, top to bottom: from the
  /// focused one, Down until Down moves no further.
  Future<List<String>> walkEveryRow(String screen, {int maxDown = 16}) async {
    final walked = <String>[];
    final seen = <ScrollableState>{};
    for (var i = 0; i <= maxDown; i++) {
      final row = focusedRow;
      if (row != null && seen.add(row)) {
        final name = '$screen row ${walked.length + 1} (${describeFocus()})';
        await walkRow(name);
        walked.add(name);
      }
      final before = focus;
      await down();
      if (focus == before) break;
    }
    return walked;
  }
}
