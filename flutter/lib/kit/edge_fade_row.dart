import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
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

  /// How strongly the leading edge fades, 0–1, in place of [fadeStart]'s
  /// on/off — see [EdgeFadeRow.scrolled]. A scroll-driven fade that only
  /// switches off at offset 0 vanishes in one frame just after the list
  /// lands; eased by the offset it has gone by the time it gets there.
  final double? startStrength;

  const EdgeFadeRow({
    super.key,
    required this.child,
    this.fadeWidth = _defaultFadeWidth,
    this.axis = Axis.horizontal,
    this.fadeStart = true,
    this.fadeEnd = true,
    this.startStrength,
  });

  /// A leading fade that grows over the first [fadeWidth] of scroll and
  /// shrinks back the same way, instead of switching at offset 0.
  static double strengthFor(
    BuildContext context,
    ScrollController controller, {
    double fadeWidth = _defaultFadeWidth,
  }) {
    if (!controller.hasClients) return 0;
    final width = fadeWidth.du(context);
    return width <= 0 ? 0 : (controller.offset / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final extent = axis == Axis.horizontal ? bounds.width : bounds.height;
        final scaledFadeWidth = fadeWidth.du(context);
        final fraction = extent > 0
            ? (scaledFadeWidth / extent).clamp(0.0, 0.5)
            : 0.0;
        final strength = startStrength ?? (fadeStart ? 1.0 : 0.0);
        final startColor = AppColors.ink.withValues(alpha: 1 - strength);
        final endColor = fadeEnd ? AppColors.transparent : AppColors.ink;
        return AppGradients.linear(
          begin: axis == Axis.horizontal
              ? Alignment.centerLeft
              : Alignment.topCenter,
          end: axis == Axis.horizontal
              ? Alignment.centerRight
              : Alignment.bottomCenter,
          colors: [startColor, AppColors.ink, AppColors.ink, endColor],
          stops: [0.0, fraction, 1 - fraction, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
