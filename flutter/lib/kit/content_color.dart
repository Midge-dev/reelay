import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Ports ui/kit/Theme.kt's `LocalContentColor` — the ambient color that
/// Text/Icon resolve against, overridden by FocusableSurface per focus
/// state the same way Compose's CompositionLocalProvider does.
class ContentColor extends InheritedWidget {
  final Color color;

  const ContentColor({super.key, required this.color, required super.child});

  static Color of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ContentColor>();
    return widget?.color ?? AppColors.ink;
  }

  @override
  bool updateShouldNotify(ContentColor oldWidget) => color != oldWidget.color;
}
