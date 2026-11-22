import 'package:flutter/widgets.dart';

import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'app_loading_indicator.dart';
import 'loading_lines.dart';

/// The full-screen wait, with a randomly-picked "flavor" line under the real
/// status message, purely for personality on what's otherwise a blank
/// wait — picked once per mount (not re-randomized on every rebuild, which
/// would just look like flickering text).
///
/// `message` is optional: pass it only when it conveys something the
/// flavor line doesn't (e.g. "Logged in as $username — connecting to
/// library…"). A generic "Loading X…" tells the user nothing they don't
/// already know from having just clicked X, and reads as redundant next to
/// the flavor line — omit it in that case.
class LoadingScreen extends StatefulWidget {
  final String? message;

  const LoadingScreen([this.message, Key? key]) : super(key: key);

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final _flavor =
      pickLoadingLine();

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoadingIndicator(),
            SizedBox(height: 16.du(context)),
            if (message != null) ...[
              AppText(message),
              SizedBox(height: 4.du(context)),
            ],
            AppText(
              _flavor,
              style: AppTypography.caption,
              color: AppColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
