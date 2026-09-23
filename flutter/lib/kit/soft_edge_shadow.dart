import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';

/// A slide-in panel's shadow, drawn as an eased strip beside its edge
/// rather than a [BoxShadow]: a box shadow's blur is in raw pixels (not
/// scaled with the UI), so on a TV it was a short, stepped dark band.
/// [AppGradients] eases it out from the panel edge to clear.
class SoftEdgeShadow extends StatelessWidget {
  /// Which way the shadow falls from the panel's edge.
  final AxisDirection toward;

  const SoftEdgeShadow({super.key, this.toward = AxisDirection.right});

  /// How far the shadow reaches, in du.
  static const extent = 120.0;

  /// The overlay elevation's shadow colour at the panel edge.
  static const _shadow = Color(0xFF06070C);

  @override
  Widget build(BuildContext context) {
    final fromRight = toward == AxisDirection.left;
    return IgnorePointer(
      child: SizedBox(
        width: extent.du(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppGradients.linear(
              begin: fromRight ? Alignment.centerRight : Alignment.centerLeft,
              end: fromRight ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                _shadow.withValues(alpha: 0.55),
                _shadow.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
