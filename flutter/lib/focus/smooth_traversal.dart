import 'package:flutter/widgets.dart';

import '../kit/scroll_peek.dart';
import '../theme/tokens.dart';

/// The app's focus traversal: Flutter's reading-order policy, but the
/// scroll that brings a newly focused widget into view eases there instead
/// of jumping. Flutter's default does that scroll with a zero duration, so
/// every Up/Down between rows cut the page to its new place; now it glides,
/// on [AppMotion.pageScroll] and the enter curve.
///
/// Focus itself still moves at once — only the scroll animates, so holding
/// a direction never waits on it; each press retargets the one scroll.
/// Installed once at the root (main.dart), so every screen gets it. At
/// [MotionLevel.minimal] it cuts again, like page transitions.
FocusTraversalPolicy smoothFocusTraversalPolicy() =>
    ReadingOrderTraversalPolicy(requestFocusCallback: _requestFocusAndEase);

void _requestFocusAndEase(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final context = node.context;
  if (context == null) return;
  // Each scrollable around it, innermost first, as Scrollable.ensureVisible
  // does — except a horizontal row, which only moves when focus goes past
  // its edge (revealInRow); aligning every card in it moved the row on
  // every press.
  final duration = AppMotion.animatePages ? AppMotion.pageScroll : Duration.zero;
  final card = context.findRenderObject();
  if (card == null) return;
  // What each scrollable is asked to show: its own child that holds the
  // card, and — as Scrollable.ensureVisible does — the card within it, so
  // the page around a row brings the card on screen, not the whole row.
  RenderObject? holder = card;
  var scrollable = Scrollable.maybeOf(context);
  while (holder != null && scrollable != null) {
    if (axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
      revealInRow(card, scrollable, duration: AppMotion.animatePages ? AppMotion.rowScroll : Duration.zero);
    } else {
      scrollable.position.ensureVisible(
        holder,
        targetRenderObject: identical(holder, card) ? null : card,
        alignment: alignment ?? 1,
        alignmentPolicy: alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
        duration: followDuration(scrollable.position, duration),
        curve: AppMotion.enter,
      );
    }
    holder = scrollable.context.findRenderObject();
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
}
