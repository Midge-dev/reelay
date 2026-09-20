import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const _forwardAlignment = 0.8;
const _backwardAlignment = 0.0;

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
void ensureCardVisible(BuildContext context, {Duration duration = const Duration(milliseconds: 200)}) {
  final movingForward = _isMovingForward(context);
  if (movingForward == null) return;

  Scrollable.ensureVisible(
    context,
    alignment: movingForward ? _forwardAlignment : _backwardAlignment,
    duration: duration,
  );
}

/// Same idea as [ensureCardVisible], but for a multi-row grid where the
/// proportional 0.8 alignment doesn't reliably leave a *row's* worth of
/// peek — the fraction of the viewport one row occupies varies with row
/// height, unlike a horizontal row of cards sized to roughly match a
/// fifth of the viewport width. [peekExtent] instead pins the peek to a
/// fixed pixel amount (matching the caller's fade-affordance width),
/// computing whatever alignment fraction currently produces that.
void ensureRowVisible(BuildContext context, {required double peekExtent, Duration duration = const Duration(milliseconds: 200)}) {
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
