import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

/// Ports ui/common/WatchTogetherIcon.kt — two overlapping dots.
class WatchTogetherIcon extends StatelessWidget {
  const WatchTogetherIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 23.du(context),
      height: 14.du(context),
      child: Stack(
        children: [
          Container(
            width: 14.du(context),
            height: 14.du(context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent300,
            ),
          ),
          Positioned(
            left: 9.du(context),
            child: Container(
              width: 14.du(context),
              height: 14.du(context),
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
