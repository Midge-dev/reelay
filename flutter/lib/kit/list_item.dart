import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'surface_style.dart';

const _listItemShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));
const _listItemPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

final _listItemColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.white,
  focusedContainer: AppColors.accent,
  selectedContainer: AppColors.accent.withValues(alpha: 0.35),
);

/// Ports ui/kit/ListItem.kt — used by the nav rail, Settings' server list,
/// and the player's subtitle/quality menus.
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
        shape: _listItemShape,
        colors: _listItemColors,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: _listItemPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 16)],
              headline,
            ],
          ),
        ),
      ),
    );
  }
}
