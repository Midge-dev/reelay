import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Stands in for a screen that hasn't been ported yet (Phase 4). Exists so
/// AppRoot's switch is exhaustive and runnable from Phase 0 onward.
class PlaceholderScreen extends StatelessWidget {
  final String label;

  const PlaceholderScreen({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: AppTypography.title2.copyWith(color: AppColors.ink)),
    );
  }
}
