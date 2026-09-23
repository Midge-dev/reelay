import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

const _cardWidth = 372.0;
const _cardHeight = 209.0;
// Per-card base opacity before the pulse multiplies on top — screen 02's
// own values, so the row fades toward its trailing edge.
const _cardBaseOpacities = [1.0, 0.82, 0.68, 0.6];
// Caption bar widths as fractions of the card, per screen 02.
const _captionWidths = [(0.70, 0.45), (0.60, 0.40), (0.75, 0.50), (0.55, 0.38)];
const _heroTopInset = 120.0;
const _heroGap = 20.0;

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

class _HomeLoadingSkeletonState extends State<HomeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.skeletonPulse,
      vsync: this,
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 0.6).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // The second, dimmer placeholder tone screen 02 uses for secondary lines:
  // a little over halfway from ground to surface.
  Color get _dim => Color.lerp(AppColors.background, AppColors.surface, 0.57)!;

  Widget _block({
    required double width,
    required double height,
    double radius = 4,
    Color? color,
  }) {
    return Container(
      width: width.du(context),
      height: height.du(context),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius.du(context)),
      ),
    );
  }

  Widget _card(int i) {
    final (title, sub) = _captionWidths[i];
    return Opacity(
      opacity: _cardBaseOpacities[i],
      child: SizedBox(
        width: _cardWidth.du(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _block(
              width: _cardWidth,
              height: _cardHeight,
              radius: AppShape.radiusMd,
            ),
            SizedBox(height: AppSpacing.md.du(context)),
            _block(width: _cardWidth * title, height: 18),
            SizedBox(height: AppSpacing.sm.du(context)),
            _block(width: _cardWidth * sub, height: 16, color: _dim),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: _heroGap.du(context));
    // One whole-screen opacity breath (not per block, not a sweep): a
    // single AnimatedBuilder repainting one layer.
    return ColoredBox(
      color: AppColors.background,
      child: FadeTransition(
        opacity: _pulse,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.safeX.du(context),
                      _heroTopInset.du(context),
                      AppSpacing.safeX.du(context),
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _block(width: 110, height: 17),
                        gap,
                        _block(
                          width: 640,
                          height: 62,
                          radius: AppShape.radiusSm,
                        ),
                        gap,
                        _block(width: 520, height: 19, color: _dim),
                        gap,
                        _block(width: 380, height: 4, radius: 2),
                        gap,
                        _block(width: 660, height: 21, color: _dim),
                        SizedBox(height: (_heroGap + 10).du(context)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _block(
                              width: 180,
                              height: 62,
                              radius: AppShape.radiusMd,
                            ),
                            SizedBox(width: AppSpacing.lg.du(context)),
                            _block(
                              width: 230,
                              height: 62,
                              radius: AppShape.radiusMd,
                              color: _dim,
                            ),
                            SizedBox(width: AppSpacing.lg.du(context)),
                            _block(
                              width: 170,
                              height: 62,
                              radius: AppShape.radiusMd,
                              color: _dim,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.safeX.du(context),
                      top: 28.du(context),
                      bottom: AppSpacing.safeY.du(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _block(width: 220, height: 22),
                        SizedBox(height: AppSpacing.lg.du(context)),
                        // Rows bleed off the right edge (DESIGN.md
                        // layout) — clip rather than overflow when the
                        // four cards are wider than the screen.
                        ClipRect(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var i = 0;
                                  i < _cardBaseOpacities.length;
                                  i++
                                ) ...[
                                  if (i > 0)
                                    SizedBox(
                                      width: AppSpacing.cardGap.du(context),
                                    ),
                                  _card(i),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
