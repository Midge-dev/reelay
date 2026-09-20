import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

const _defaultFadeWidth = 48.0;

/// Fades the left/right edges of a horizontally-scrolling row to hint that
/// more content continues off-screen — the same edge affordance most TV
/// browsing UIs (Netflix, Plex, etc.) use. Always on regardless of scroll
/// position, matching that same convention, rather than only appearing
/// once there's genuinely more content in that direction.
class EdgeFadeRow extends StatelessWidget {
  final Widget child;
  final double fadeWidth;

  const EdgeFadeRow({super.key, required this.child, this.fadeWidth = _defaultFadeWidth});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final fraction = bounds.width > 0 ? (fadeWidth / bounds.width).clamp(0.0, 0.5) : 0.0;
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [AppColors.transparent, AppColors.white, AppColors.white, AppColors.transparent],
          stops: [0.0, fraction, 1 - fraction, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
