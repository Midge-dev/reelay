import 'package:flutter/widgets.dart';

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
  Scrollable.ensureVisible(
    context,
    alignment: alignment ?? 1,
    alignmentPolicy: alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
    duration: AppMotion.animatePages ? AppMotion.pageScroll : Duration.zero,
    curve: AppMotion.enter,
  );
}
