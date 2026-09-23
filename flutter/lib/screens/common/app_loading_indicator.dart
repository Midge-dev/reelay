import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

const _strokeWidth = 4.0;
const _sweepDegrees = 90.0;
const _size = 56.0;

/// Ports ui/common/AppLoadingIndicator.kt — a rotating purple arc over a
/// full gray track, not a stock spinner.
class AppLoadingIndicator extends StatefulWidget {
  const AppLoadingIndicator({super.key});

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size.du(context),
      height: _size.du(context),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ArcPainter(
            _controller.value * 360,
            _strokeWidth.du(context),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double rotationDegrees;
  final double strokeWidth;

  _ArcPainter(this.rotationDegrees, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    canvas.drawArc(
      rect,
      rotationDegrees * math.pi / 180,
      _sweepDegrees * math.pi / 180,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.rotationDegrees != rotationDegrees ||
      oldDelegate.strokeWidth != strokeWidth;
}
