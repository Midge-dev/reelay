import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _fadeInMs = 500;

/// Placeholder splash while a real logo design is in progress — plain
/// wordmark text and a simple fade-in, no logo asset. Swap back to a real
/// mark/wordmark image pair (see git history for the previous animated
/// version) once that design lands.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(duration: const Duration(milliseconds: _fadeInMs), vsync: this)..forward();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _fadeIn, curve: Curves.fastOutSlowIn),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reelay', style: AppTypography.title1.copyWith(color: AppColors.inkOnArt)),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Watch together', style: AppTypography.body.copyWith(color: AppColors.inkOnArt.withValues(alpha: 0.7))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
