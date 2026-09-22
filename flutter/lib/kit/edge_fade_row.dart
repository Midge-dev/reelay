import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

const _defaultFadeWidth = 48.0;

/// Fades the leading/trailing edges of a scrolling row or grid to hint that
/// more content continues off-screen — the same edge affordance most TV
/// browsing UIs (Netflix, Plex, etc.) use. Always on regardless of scroll
/// position, matching that same convention, rather than only appearing
/// once there's genuinely more content in that direction.
///
/// Defaults to a horizontal fade on both edges (its original, and still
/// most common, use). [axis] switches to a vertical (top/bottom) fade for a
/// vertically-scrolling grid; [fadeStart]/[fadeEnd] drop either edge's fade
/// — e.g. a grid right below a header only wants the bottom edge softened,
/// not the top.
class EdgeFadeRow extends StatelessWidget {
  final Widget child;
  final double fadeWidth;
  final Axis axis;
  final bool fadeStart;
  final bool fadeEnd;

  const EdgeFadeRow({
    super.key,
    required this.child,
    this.fadeWidth = _defaultFadeWidth,
    this.axis = Axis.horizontal,
    this.fadeStart = true,
    this.fadeEnd = true,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final extent = axis == Axis.horizontal ? bounds.width : bounds.height;
        final fraction = extent > 0 ? (fadeWidth / extent).clamp(0.0, 0.5) : 0.0;
        final startColor = fadeStart ? AppColors.transparent : AppColors.ink;
        final endColor = fadeEnd ? AppColors.transparent : AppColors.ink;
        return LinearGradient(
          begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: [startColor, AppColors.ink, AppColors.ink, endColor],
          stops: [0.0, fraction, 1 - fraction, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
