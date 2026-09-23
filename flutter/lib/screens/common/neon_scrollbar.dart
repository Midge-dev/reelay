import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

const _width = 4.0;
const _minThumbHeight = 24.0;

/// A hand-drawn vertical scroll
/// indicator (no native TV scrollbar widget existed on Android either).
class NeonScrollbar extends StatelessWidget {
  final ScrollController controller;

  const NeonScrollbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width.du(context),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          painter: _NeonScrollbarPainter(
            controller,
            _minThumbHeight.du(context),
          ),
        ),
      ),
    );
  }
}

class _NeonScrollbarPainter extends CustomPainter {
  final ScrollController controller;
  final double minThumbHeight;

  _NeonScrollbarPainter(this.controller, this.minThumbHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final cornerRadius = Radius.circular(size.width / 2);
    final trackRect = RRect.fromRectAndRadius(Offset.zero & size, cornerRadius);
    canvas.drawRRect(trackRect, Paint()..color = AppColors.line);

    if (!controller.hasClients || !controller.position.hasContentDimensions)
      return;
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent <= 0) return;

    final totalExtent = size.height + maxExtent;
    final thumbHeight = (size.height * size.height / totalExtent).clamp(
      minThumbHeight,
      size.height,
    );
    final offset = controller.offset.clamp(0.0, maxExtent);
    final thumbTop = (size.height - thumbHeight) * (offset / maxExtent);

    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, thumbTop, size.width, thumbHeight),
      cornerRadius,
    );
    // Flat fill, not a gradient — Nocturne's one accent never appears as a
    // glow or gradient, only as a line, a spine or a mark. DESIGN.md #4/#8.
    canvas.drawRRect(thumbRect, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant _NeonScrollbarPainter oldDelegate) => true;
}
