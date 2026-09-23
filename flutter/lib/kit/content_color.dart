import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The ambient color that
/// Text/Icon resolve against, overridden by FocusableSurface per focus
/// state.
class ContentColor extends InheritedWidget {
  final Color color;

  const ContentColor({super.key, required this.color, required super.child});

  /// The ambient colour only when a surface actually provides one.
  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentColor>()?.color;

  static Color of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ContentColor>();
    return widget?.color ?? AppColors.ink;
  }

  @override
  bool updateShouldNotify(ContentColor oldWidget) => color != oldWidget.color;
}
