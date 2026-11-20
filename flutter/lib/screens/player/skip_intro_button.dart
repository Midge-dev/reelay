import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';

/// "Skip intro", bottom-right where the Up Next card sits, while the
/// episode is in its intro (see PlayerScreen._updateSkipIntro). Not in the
/// Nocturne handoff yet: it's the kit's filled button — an opaque surface,
/// so its words never sit on raw video — with the elevation the Up Next
/// card floats on.
///
/// The controls bar routes its arrows by hand, so this does too: Down goes
/// back to the controls ([onDown]); Left, Right and Up go nowhere while the
/// controls are up — there's nothing beside or above it — and otherwise
/// fall through to the screen, which seeks or brings up the controls.
class SkipIntroButton extends StatelessWidget {
  final VoidCallback onSkip;
  final FocusNode focusNode;
  final bool controlsVisible;
  final VoidCallback onDown;

  const SkipIntroButton({
    super.key,
    required this.onSkip,
    required this.focusNode,
    required this.controlsVisible,
    required this.onDown,
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && controlsVisible) {
      onDown();
      return KeyEventResult.handled;
    }
    if (controlsVisible &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
          boxShadow: AppElevation.overlay,
        ),
        child: AppButton(
          onClick: onSkip,
          focusNode: focusNode,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(PhosphorIconsRegular.skipForward, size: 20),
              SizedBox(width: AppSpacing.sm.du(context)),
              const AppText('Skip intro'),
            ],
          ),
        ),
      ),
    );
  }
}
