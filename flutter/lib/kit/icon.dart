import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import 'content_color.dart';

/// Tints a glyph with the ambient ContentColor
/// unless a tint is passed explicitly. IconData comes from whatever icon
/// set the caller uses (e.g. Icons.* from package:flutter/material.dart —
/// importing just the IconData constants doesn't pull in Material
/// widgets/theming — glyphs only, not the component library).
class AppIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? tint;

  const AppIcon(this.icon, {super.key, this.size = 24, this.tint});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size.du(context),
      color: tint ?? ContentColor.of(context),
    );
  }
}
