import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// Ports ui/common/WatchTogetherIcon.kt — two overlapping dots.
class WatchTogetherIcon extends StatelessWidget {
  const WatchTogetherIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 23,
      height: 14,
      child: Stack(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent300,
            ),
          ),
          Positioned(
            left: 9,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
