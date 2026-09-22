import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

RoundedRectangleBorder _listItemShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
const _listItemHeight = 96.0;
const _listItemPaddingHorizontal = AppSpacing.xl;

final _listItemColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContent: AppColors.ink,
);
final _listItemBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/kit/ListItem.kt — used by Settings' server list and the
/// player's subtitle/quality menus.
class AppListItem extends StatelessWidget {
  final bool selected;
  final VoidCallback onClick;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget? leading;
  final Widget headline;

  const AppListItem({
    super.key,
    required this.selected,
    required this.onClick,
    this.focusNode,
    this.autofocus = false,
    this.leading,
    required this.headline,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        autofocus: autofocus,
        shape: _listItemShape(context),
        colors: _listItemColors,
        border: _listItemBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          height: _listItemHeight.du(context),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _listItemPaddingHorizontal.du(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  leading!,
                  SizedBox(width: AppSpacing.lg.du(context)),
                ],
                headline,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
