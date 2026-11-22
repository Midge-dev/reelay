import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';

/// How far past its edges a horizontal row builds its cards: a screen's
/// width each way. A held D-pad moves focus a card every repeat (~50 ms)
/// while the row's scroll eases after it; with Flutter's default (250 px,
/// about a card and a half) focus soon ran past the cards that existed, and
/// the press found nothing to move to — a held key stopped short of the end
/// of a long row (the row journeys' "holding Right, focus keeps up").
double rowCacheExtent(BuildContext context) => MediaQuery.sizeOf(context).width;

const _forwardAlignment = 0.8;
const _backwardAlignment = 0.0;

/// In a horizontal row, see [revealInRow]: the row holds still until focus
/// goes past its edge (DESIGN.md). What follows is for vertical grids.
///
/// Scrolls [context]'s enclosing Scrollable to bring it on screen, biasing
/// which side gets left "peeking" based on which way focus is actually
/// moving — forward (deeper into the list) leaves the *next* item partially
/// visible (alignment near the far edge); backward reveals the target
/// flush against the near edge instead.
///
/// A fixed `alignment: 0.8` (the original scroll-peek implementation)
/// repositions *every* newly-focused card to 80% across the viewport, even
/// one moving backward through the list — each press of the key toward the
/// start yanks the viewport back by several cards' width instead of one,
/// since it's always re-centering on 80% rather than revealing minimally.
/// Comparing the target's reveal-at-leading-edge offset against the
/// Scrollable's current position tells us which way we're actually
/// headed, without needing every caller to track and pass its own index.
void ensureCardVisible(BuildContext context, {Duration duration = AppMotion.rowScroll}) {
  // A horizontal row only moves when focus goes past its edge (DESIGN.md).
  final scrollable = Scrollable.maybeOf(context);
  final target = context.findRenderObject();
  if (scrollable != null && target != null && axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
    revealInRowAndPage(target, context, duration: duration);
    return;
  }
  final movingForward = _isMovingForward(context);
  if (movingForward == null) return;

  Scrollable.ensureVisible(
    context,
    alignment: movingForward ? _forwardAlignment : _backwardAlignment,
    duration: duration,
    curve: AppMotion.enter,
  );
}

/// Same idea as [ensureCardVisible], but for a multi-row grid where the
/// proportional 0.8 alignment doesn't reliably leave a *row's* worth of
/// peek — the fraction of the viewport one row occupies varies with row
/// height, unlike a horizontal row of cards sized to roughly match a
/// fifth of the viewport width. [peekExtent] instead pins the peek to a
/// fixed pixel amount (matching the caller's fade-affordance width),
/// computing whatever alignment fraction currently produces that.
void ensureRowVisible(BuildContext context, {required double peekExtent, Duration duration = AppMotion.pageScroll}) {
  // The same card can sit in a horizontal row (Home's lower rows): there
  // it follows the row rule, not the grid's.
  final scrollable = Scrollable.maybeOf(context);
  final target = context.findRenderObject();
  if (scrollable != null && target != null && axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
    revealInRowAndPage(target, context, duration: AppMotion.rowScroll);
    return;
  }
  final movingForward = _isMovingForward(context);
  if (movingForward == null) return;
  final scrollableState = Scrollable.maybeOf(context);
  if (scrollableState == null) return;

  final viewportExtent = scrollableState.position.viewportDimension;
  final peekAlignment = viewportExtent > 0 ? (1 - peekExtent / viewportExtent).clamp(0.0, 1.0) : _forwardAlignment;

  Scrollable.ensureVisible(
    context,
    alignment: movingForward ? peekAlignment : _backwardAlignment,
    duration: duration,
    curve: AppMotion.enter,
  );
}

/// Null when there's no enclosing Scrollable/viewport to judge direction
/// against (matches the previous no-op behavior of just returning early).
bool? _isMovingForward(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject == null) return null;
  final scrollableState = Scrollable.maybeOf(context);
  if (scrollableState == null) return null;
  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport == null) return null;

  final leadingEdgeOffset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
  return leadingEdgeOffset >= scrollableState.position.pixels;
}

/// DESIGN.md: a horizontal row holds still while focus moves between cards
/// it already shows whole, and scrolls only when focus moves to a card past
/// an edge — just far enough to show that card whole, at the edge. The
/// edge is the safe margin, where the row's fade starts: a card reaching
/// into it is off the edge. Used by every card that scrolls itself into
/// view, and by the app's traversal policy for anything else in a row.
void revealInRow(RenderObject target, ScrollableState row, {Duration duration = AppMotion.rowScroll}) {
  final viewport = RenderAbstractViewport.maybeOf(target);
  if (viewport == null) return;
  final position = row.position;
  final inset = AppSpacing.safeX.du(row.context);
  // The scroll offsets that put the card's leading edge at the row's
  // leading edge, and its trailing edge at the trailing one.
  final leading = viewport.getOffsetToReveal(target, 0).offset;
  final trailing = viewport.getOffsetToReveal(target, 1).offset;
  double? to;
  if (position.pixels > leading - inset) {
    to = leading - inset; // past the leading edge
  } else if (position.pixels < trailing + inset) {
    to = trailing + inset; // past the trailing edge
  }
  if (to == null) return;
  // Within a margin of either end, go to the end: the first and last cards
  // sit where they would at rest (a card's label can be wider than the part
  // that takes focus — a cast member's name under their picture).
  if (position.maxScrollExtent - to < inset) to = position.maxScrollExtent;
  if (to - position.minScrollExtent < inset) to = position.minScrollExtent;
  to = to.clamp(position.minScrollExtent, position.maxScrollExtent);
  if ((to - position.pixels).abs() < 0.5) return;
  if (duration == Duration.zero || !AppMotion.animatePages) {
    position.jumpTo(to);
  } else {
    position.animateTo(to, duration: duration, curve: AppMotion.enter);
  }
}

/// A card in a row, focused: its row follows [revealInRow], and every
/// vertical scrollable around the row — the page — moves only if the card
/// is off it, and then just far enough to show it. (Focus moved by code —
/// Undo putting it back, a screen restoring it — gets no traversal scroll,
/// so this has to bring the row on screen too.)
void revealInRowAndPage(RenderObject card, BuildContext context, {Duration duration = AppMotion.rowScroll}) {
  RenderObject? holder = card;
  var scrollable = Scrollable.maybeOf(context);
  while (holder != null && scrollable != null) {
    if (axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
      revealInRow(card, scrollable, duration: duration);
    } else {
      final viewport = RenderAbstractViewport.maybeOf(holder);
      if (viewport != null) {
        final position = scrollable.position;
        final top = viewport.getOffsetToReveal(card, 0).offset;
        final bottom = viewport.getOffsetToReveal(card, 1).offset;
        final to = position.pixels > top ? top : (position.pixels < bottom ? bottom : null);
        if (to != null) {
          final clamped = to.clamp(position.minScrollExtent, position.maxScrollExtent);
          if (duration == Duration.zero || !AppMotion.animatePages) {
            position.jumpTo(clamped);
          } else {
            position.animateTo(clamped, duration: AppMotion.pageScroll, curve: AppMotion.enter);
          }
        }
      }
    }
    holder = scrollable.context.findRenderObject();
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
}
