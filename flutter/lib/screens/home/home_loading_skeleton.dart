import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

const _cardWidth = 372.0;
const _cardHeight = 209.0;
// Per-card base opacity before the pulse multiplies on top — matches
// screen 02's mockup, where each card in the row dims a little further so
// the whole row doesn't strobe as one flat block.
const _cardBaseOpacities = [1.0, 0.82, 0.68, 0.6];

/// Screen 02 — Home, loading. Real geometry at elev2 (not a spinner): the
/// rail and hero frame paint immediately, and a 2.4s whole-row opacity
/// breath (AppMotion.skeletonPulse) stands in for content while the first
/// Home payload is in flight. Not a gradient sweep — that's a per-frame
/// repaint of the full row, which is exactly what a weak box can't afford
/// while it's also decoding artwork. Used only for the very first Home
/// load ([LoadingHome] in app_root.dart); every other loading state
/// (auth, section switches) keeps the generic [LoadingScreen] spinner,
/// which has no equivalent "known shape" to skeleton against.
class HomeLoadingSkeleton extends StatefulWidget {
  const HomeLoadingSkeleton({super.key});

  @override
  State<HomeLoadingSkeleton> createState() => _HomeLoadingSkeletonState();
}

class _HomeLoadingSkeletonState extends State<HomeLoadingSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: AppMotion.skeletonPulse, vsync: this)..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 0.6).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block({required double width, required double height, double opacity = 1}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Opacity(
        opacity: _pulse.value * opacity,
        child: Container(
          width: width.du(context),
          height: height.du(context),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.xxxl.du(context), AppSpacing.xxxl.du(context), AppSpacing.xxxl.du(context), 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(width: 110, height: 17),
            SizedBox(height: AppSpacing.md.du(context)),
            _block(width: 640, height: 62),
            SizedBox(height: AppSpacing.md.du(context)),
            _block(width: 520, height: 19),
            SizedBox(height: AppSpacing.md.du(context)),
            _block(width: 380, height: 4),
            SizedBox(height: AppSpacing.md.du(context)),
            _block(width: 660, height: 21),
            SizedBox(height: AppSpacing.lg.du(context)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _block(width: 160, height: 62),
                SizedBox(width: AppSpacing.md.du(context)),
                _block(width: 220, height: 62),
              ],
            ),
            SizedBox(height: AppSpacing.xxl.du(context)),
            _block(width: 220, height: 22),
            SizedBox(height: AppSpacing.lg.du(context)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _cardBaseOpacities.length; i++) ...[
                  if (i > 0) SizedBox(width: AppSpacing.xl.du(context)),
                  _block(width: _cardWidth, height: _cardHeight, opacity: _cardBaseOpacities[i]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
