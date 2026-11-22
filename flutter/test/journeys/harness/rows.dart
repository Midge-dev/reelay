import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journey.dart';

/// DESIGN.md's row rules, checked on a real row with the remote:
///
/// - the focused card is whole on screen, its focus scale and border never
///   clipped by the row's track ("A row's track is card height +
///   rowHeadroom … never clipped");
/// - moving on, the row stops with the focused card ~80% across, so the
///   next card peeks ("the next card stays half-visible");
/// - the last card stops flush with the row's end (RowEndStop);
/// - moving back reveals one card at a time, never yanks the row;
/// - a held direction lands where the presses say, and the row then sits
///   still ("scrolls the row once, when the key settles").
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

  /// The next card along [row] after [from], if one is built.
  Rect? _nextCard(ScrollableState row, Rect from) {
    Rect? next;
    for (final node in FocusManager.instance.rootScope.descendants) {
      final context = node.context;
      if (context == null || !node.canRequestFocus || node.skipTraversal) continue;
      if (Scrollable.maybeOf(context, axis: Axis.horizontal) != row) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = _rectOf(context);
      if (rect.left >= from.right - 1 && (next == null || rect.left < next.left)) next = rect;
    }
    return next;
  }

  /// Which card is focused, by its place along the row's content — the
  /// same card at any scroll (its text can be an initial, its box moves).
  int _cardAt(ScrollableState row) => (focusedRect()!.left - _rectOf(row.context).left + row.position.pixels).round();

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
    final cards = <int>[_cardAt(row)];
    _expectCardWhole(row, '$name, first card');

    // Right to the end.
    while (cards.length < 60) {
      final before = focus;
      await right();
      if (focus == before || focusedRow != row) {
        if (focusedRow != row) await left(); // Right left the row: come back
        break;
      }
      cards.add(_cardAt(row));
      final here = '$name, card ${cards.length}';
      _expectCardWhole(row, here);
      // More than a card still hidden past the edge: the next one peeks.
      if (position.extentAfter > focusedRect()!.width) {
        final next = _nextCard(row, focusedRect()!);
        expect(next != null && next.left < _visible(row).right - 1, isTrue,
            reason: why('$here: the row has more, so the next card should peek in (${next ?? 'none built'})'));
      }
    }
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent + 0.5),
        reason: why('$name: the last card stops flush, not past the end'));
    if (position.maxScrollExtent > 0) {
      expect(position.pixels, closeTo(position.maxScrollExtent, 1),
          reason: why('$name: at its last card the row is scrolled to its end'));
    }

    // Back to the start, one card at a time.
    final cardStep = focusedRect()!.width * 1.6; // a card and its gap, with room
    for (var i = cards.length - 1; i > 0; i--) {
      final from = position.pixels;
      await left();
      final here = '$name, back to card $i';
      expect(_cardAt(row), closeTo(cards[i - 1], 2), reason: why('$here: Left goes back one card'));
      expect((from - position.pixels).abs(), lessThanOrEqualTo(cardStep),
          reason: why('$here: moving back reveals one card, it doesn\'t yank the row (${from - position.pixels} px)'));
      _expectCardWhole(row, here);
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
