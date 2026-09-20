import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Ports ui/kit/Type.kt exactly (fontSize/lineHeight/weight) — this is the
/// real source of truth, superseding Phase 0's placeholder first pass.
/// `height` below is a multiplier of fontSize (Flutter's TextStyle.height
/// convention), computed from Kotlin's absolute lineHeight/fontSize ratio.
class AppTypography {
  AppTypography._();

  static const _color = AppColors.onBackground;

  static const displaySmall = TextStyle(fontSize: 44, height: 48 / 44, fontWeight: FontWeight.normal, color: _color);
  static const displayMedium = TextStyle(fontSize: 36, height: 40 / 36, fontWeight: FontWeight.normal, color: _color);
  static const headlineMedium = TextStyle(fontSize: 28, height: 32 / 28, fontWeight: FontWeight.normal, color: _color);
  static const titleLarge = TextStyle(fontSize: 22, height: 26 / 22, fontWeight: FontWeight.w500, color: _color);
  static const titleMedium = TextStyle(fontSize: 18, height: 22 / 18, fontWeight: FontWeight.w500, color: _color);
  static const bodyLarge = TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.normal, color: _color);
  static const bodySmall = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.normal, color: _color);
}
