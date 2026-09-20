import 'package:flutter/widgets.dart';

/// Ported from docs/design-tokens.md. Android's ui/theme/AppColors.kt is
/// still the source of truth for values while it's the only shipped
/// platform — keep these in sync with that file, not the reverse.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0D0D12);
  static const onBackground = Color(0xFFF2F2F5);
  static const surface = Color(0xFF17171D);
  static const onSurface = Color(0xFFF2F2F5);
  static const surfaceVariant = Color(0xFF2A2A33);
  static const onSurfaceVariant = Color(0xFFC7C7D1);

  /// NeonPurple
  static const accent = Color(0xFFAD2BD7);

  /// NeonPurpleGlow — outer stop of the focus-glow gradient, elevation glow color.
  static const accentGlow = Color(0xFFE795FC);

  /// NeonPurplePressed — filled-surface press feedback (Button/IconButton).
  static const accentPressed = Color(0xFF8F22B3);

  static const onAccent = Color(0xFFFFFFFF);

  /// Literal white for content over video/photos/QR — max contrast on
  /// unpredictable backdrops, deliberately not onBackground.
  static const white = Color(0xFFFFFFFF);

  static const scrim = Color(0xFF000000);

  static const transparent = Color(0x00000000);

  /// Idle/unfocused outline (inputs, idle card borders).
  static const dimBorder = Color(0xFF444444);

  /// Disabled content: apply 50% alpha to whichever content color is in
  /// play (onSurface/onAccent), not a separate flat color.
  static Color disabled(Color contentColor) => contentColor.withValues(alpha: 0.5);
}

/// Spacing scale, derived from actual usage frequency in the Android
/// codebase — treat as canonical rather than picking new numbers per screen.
/// Unitless in the token doc; Flutter maps 1 unit == 1 logical pixel, tuned
/// for TV viewing distance same as Android's dp mapping.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

class AppShape {
  AppShape._();

  static const radiusSm = 8.0;
  static const borderWidth = 2.0;
}

/// Motion durations — see docs/design-tokens.md §Motion.
class AppMotion {
  AppMotion._();

  static const controlsAutoHideDelay = Duration(milliseconds: 3000);
  static const toastVisible = Duration(milliseconds: 6000);
  static const toastFadeOut = Duration(milliseconds: 300);
}

/// Focus & glow treatment — the app's visual signature. Every focusable
/// element gets a two-tone radial-gradient border (accentGlow -> accent)
/// plus a matching elevation glow, only on focus; idle is dimBorder, no glow.
/// Border + glow are one paired token, not independent choices.
class AppFocusTreatment {
  AppFocusTreatment._();

  static const idleBorderColor = AppColors.dimBorder;
  static const idleBorderWidth = AppShape.borderWidth;

  static const focusedBorderWidth = AppShape.borderWidth;
  static const focusedGlowColor = AppColors.accentGlow;
  static const focusedGlowBlurRadius = 12.0;

  /// NeonPurpleGradient — radial, glow-color center to accent edge; matches
  /// AppColors.kt exactly (a linear gradient reads visibly different).
  static const focusedGradient = RadialGradient(
    colors: [AppColors.accentGlow, AppColors.accent],
  );

  /// NeonPurpleProgressGradient — horizontal, accent to glow-color; used by
  /// the player's scrub bar, not the focus border.
  static const progressGradient = LinearGradient(
    colors: [AppColors.accent, AppColors.accentGlow],
  );
}
