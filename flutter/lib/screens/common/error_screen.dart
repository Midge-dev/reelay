import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Something asked for didn't happen (DESIGN.md #11: a dialog when
/// something just asked for failed): the cause in one plain sentence,
/// and a focused way back to where you were — never a line of text on an
/// empty screen with nothing for the remote to land on. Same shape as
/// screen 25 (PlaybackFailedScreen).
class ErrorScreen extends StatefulWidget {
  /// The cause, in a sentence — never an exception string.
  final String message;
  final VoidCallback onBack;

  const ErrorScreen({super.key, required this.message, required this.onBack});

  @override
  State<ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<ErrorScreen> {
  final _back = FocusNode(debugLabel: 'error-back');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _back.requestFocus();
    });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Container(
          width: 760.du(context),
          padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
          decoration: BoxDecoration(
            color: AppColors.surfaceOverlay,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
            boxShadow: AppElevation.overlay,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(
                    PhosphorIconsRegular.warning,
                    size: 28,
                    tint: AppColors.warning,
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppText(
                    "COULDN'T DO THAT",
                    style: AppTypography.micro,
                    color: AppColors.warning,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xl.du(context)),
              AppText(widget.message, style: AppTypography.title2),
              SizedBox(height: AppSpacing.xxl.du(context)),
              AppButton(
                onClick: widget.onBack,
                focusNode: _back,
                child: const AppText('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
