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
  final renderObject = context.findRenderObject();
  if (renderObject == null) return;
  final scrollableState = Scrollable.maybeOf(context);
  if (scrollableState == null) return;
  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport == null) return;

  final leadingEdgeOffset = viewport.getOffsetToReveal(renderObject, 0.0).offset;
  final movingForward = leadingEdgeOffset >= scrollableState.position.pixels;

  Scrollable.ensureVisible(
    context,
    alignment: movingForward ? _forwardAlignment : _backwardAlignment,
    duration: duration,
  );
}
