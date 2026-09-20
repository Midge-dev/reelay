import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'app_loading_indicator.dart';

const _flavorMessages = [
  'Buttering the popcorn…',
  'Untangling the film reel…',
  'Dimming the house lights…',
  'Rewinding to the good part…',
  'Waking up the projectionist…',
  'Finding your seat…',
  'Polishing the popcorn bucket…',
  'Cueing up the trailers…',
  'Sweet-talking the server…',
  'Chasing down the end credits…',
  'Shushing the back row…',
  'Refilling the soda machine…',
];

/// Ports ui/common/LoadingScreen.kt, plus a small bit of delight the
/// Kotlin source never had: a randomly-picked "flavor" line under the real
/// status message, purely for personality on what's otherwise a blank
/// wait — picked once per mount (not re-randomized on every rebuild, which
/// would just look like flickering text).
class LoadingScreen extends StatefulWidget {
  final String message;

  const LoadingScreen(this.message, {super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final _flavor = _flavorMessages[Random().nextInt(_flavorMessages.length)];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoadingIndicator(),
            const SizedBox(height: 16),
            AppText(widget.message),
            const SizedBox(height: 4),
            AppText(_flavor, style: AppTypography.bodySmall, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
