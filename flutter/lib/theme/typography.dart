import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Reelay type scale. Sizes are 1080p logical pixels and double at 4K. Two
/// weights only — hierarchy is size and space, never boldness. The smallest
/// role is 17, which is the floor for a 3 m viewing distance.
class AppTypography {
  AppTypography._();

  static const _ink = AppColors.ink;

  /// Hero titles.
  static const display = TextStyle(
      fontSize: 62, height: 65 / 62, fontWeight: FontWeight.w500, letterSpacing: -1.55, color: _ink);

  /// Screen and detail titles.
  static const title1 = TextStyle(
      fontSize: 44, height: 48 / 44, fontWeight: FontWeight.w500, letterSpacing: -0.88, color: _ink);

  /// Dialog titles, settings group headers.
  static const title2 = TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w500, color: _ink);

  /// Row headings.
  static const rowLabel = TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w500, color: _ink);

  /// Synopsis and body copy. Clamp to 3 lines outside a detail page.
  static const body = TextStyle(
      fontSize: 21, height: 1.55, fontWeight: FontWeight.w400, color: AppColors.ink2);

  /// Card titles, list rows, button labels. w500 when focused.
  static const label = TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w400, color: _ink);

  /// Metadata and secondary lines.
  static const caption = TextStyle(
      fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w400, color: AppColors.ink3);

  /// Kickers and status. Uppercase, 0.1em tracking.
  static const micro = TextStyle(
      fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w500, letterSpacing: 1.7, color: AppColors.accent);

  /// Use for anything that updates in place — timecodes, seat counts,
  /// remaining time — so digits do not jitter.
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}
