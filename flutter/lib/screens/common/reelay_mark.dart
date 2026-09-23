import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

/// The Reelay mark from the design: two offset rounded bars, accent over
/// ink, in a 46-unit box drawn at [size] du. Painted rather than an image
/// so it follows the theme's accent and ink. (The handoff calls it a
/// placeholder for a real mark.)
class ReelayMark extends StatelessWidget {
  final double size;

  const ReelayMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size.du(context),
      child: CustomPaint(painter: _MarkPainter(accent: AppColors.accent, ink: AppColors.ink)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color accent;
  final Color ink;

  const _MarkPainter({required this.accent, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 46;
    final r = Radius.circular(4 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5 * u, 9 * u, 36 * u, 12 * u), r), Paint()..color = accent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5 * u, 25 * u, 22 * u, 12 * u), r), Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.accent != accent || old.ink != ink;
}
