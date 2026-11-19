import 'package:flutter/widgets.dart';

import '../../focus/back_handler.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// How long a removal can be taken back (DESIGN.md #12).
const undoSeconds = 8;

/// The one undo chip (screen 21): "Took Andor off the list · Undo", with a
/// rule that runs down over [undoSeconds]. Back presses Undo while it
/// lives — [backTakesPrecedence] lets it do so even while focus is
/// elsewhere (Home, where focus stays in the row it was removed from).
class UndoChip extends StatelessWidget {
  final String message;
  final IconData icon;
  final int secondsLeft;
  final FocusNode? focusNode;
  final VoidCallback onUndo;
  final double height;
  final bool backTakesPrecedence;

  const UndoChip({
    super.key,
    required this.message,
    this.icon = PhosphorIconsRegular.bookmarkSimple,
    required this.secondsLeft,
    this.focusNode,
    required this.onUndo,
    this.height = 58,
    this.backTakesPrecedence = false,
  });

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: onUndo,
      precedence: backTakesPrecedence,
      // IntrinsicWidth: the depleting rule stretches to the chip's width,
      // and the chip sits in an unbounded Row.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: (height - 3).du(context),
              child: FocusableSurface(
                onClick: onUndo,
                focusNode: focusNode,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusSm.du(context),
                  ),
                ),
                // A ground of its own: on Home it sits over the hero's art.
                colors: SurfaceColors(
                  container: AppColors.surface,
                  content: AppColors.ink2,
                  focusedContainer: AppColors.surfaceRaised,
                  focusedContent: AppColors.ink,
                ),
                border: SurfaceBorder(
                  idle: SurfaceBorderSide.solid(AppColors.line),
                  focused: SurfaceBorderSide.solid(AppColors.accent),
                ),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 22.du(context),
                    end: 10.du(context),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(icon, size: 22, tint: AppColors.accent300),
                      SizedBox(width: 18.du(context)),
                      Flexible(
                        child: AppText(
                          message,
                          style: AppTypography.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 18.du(context)),
                      Container(
                        height: 42.du(context),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.du(context),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusSm.du(context),
                          ),
                          border: Border.all(
                            color: AppColors.accent,
                            width: AppShape.borderWidth.du(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(
                              PhosphorIconsRegular.arrowCounterClockwise,
                              size: 20,
                            ),
                            SizedBox(width: 10.du(context)),
                            AppText(
                              'Undo',
                              style: AppTypography.caption,
                              color: null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(2.du(context)),
              child: SizedBox(
                height: 3.du(context),
                child: ColoredBox(
                  color: AppColors.line,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: secondsLeft / undoSeconds,
                    child: ColoredBox(color: AppColors.accent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
