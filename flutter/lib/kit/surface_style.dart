import 'package:flutter/widgets.dart';

/// Ports ui/kit/FocusableSurface.kt's `Colors` data class — named
/// SurfaceColors (not `Colors`) to avoid colliding with Flutter's own
/// Material `Colors` class if it's ever imported alongside this.
/// Unset states fall back through the same chain Kotlin's default
/// parameters do: focused -> container, pressed -> focused -> container,
/// selected/disabled -> container independently.
class SurfaceColors {
  final Color container;
  final Color content;
  final Color focusedContainer;
  final Color focusedContent;
  final Color pressedContainer;
  final Color pressedContent;
  final Color selectedContainer;
  final Color selectedContent;
  final Color disabledContainer;
  final Color disabledContent;

  SurfaceColors({
    required this.container,
    required this.content,
    Color? focusedContainer,
    Color? focusedContent,
    Color? pressedContainer,
    Color? pressedContent,
    Color? selectedContainer,
    Color? selectedContent,
    Color? disabledContainer,
    Color? disabledContent,
  })  : focusedContainer = focusedContainer ?? container,
        focusedContent = focusedContent ?? content,
        pressedContainer = pressedContainer ?? focusedContainer ?? container,
        pressedContent = pressedContent ?? focusedContent ?? content,
        selectedContainer = selectedContainer ?? container,
        selectedContent = selectedContent ?? content,
        disabledContainer = disabledContainer ?? container,
        disabledContent = disabledContent ?? content;
}

/// A single border stroke, ported from Compose's `BorderStroke` — either a
/// flat color (idle borders) or a gradient (the focus-treatment border,
/// see docs/design-tokens.md's paired border+glow token).
class SurfaceBorderSide {
  final double width;
  final Color? color;
  final Gradient? gradient;

  const SurfaceBorderSide.solid(this.color, {this.width = 2}) : gradient = null;
  const SurfaceBorderSide.gradient(this.gradient, {this.width = 2}) : color = null;
}

/// Ports FocusableSurface.kt's `Border` data class.
class SurfaceBorder {
  final SurfaceBorderSide? idle;
  final SurfaceBorderSide? focused;

  const SurfaceBorder({this.idle, this.focused});
}

/// Ports FocusableSurface.kt's `Glow` data class. Rendered via a plain
/// Flutter BoxShadow rather than the Compose source's hand-rolled 14-shell
/// blur — Compose needed that workaround because `Modifier.blur` requires
/// API 31+ and minSdk here is 26; Flutter has no such floor, so a single
/// blurred shadow is a legitimate simplification, not a missing feature.
/// Revisit with a custom-painted version only if it doesn't read right on
/// the real TV. `radius`/`alpha` default to the Kotlin source's literal
/// values (14dp/0.22) as a starting point — those were tuned for the
/// layered-blur technique's cumulative brightness, so a single BoxShadow at
/// the same alpha may read fainter and need re-tuning once seen on the
/// Shield, not assumed correct from the number alone.
class SurfaceGlow {
  final Color? focusedColor;
  final double radius;
  final double alpha;

  const SurfaceGlow({this.focusedColor, this.radius = 14, this.alpha = 0.22});
}
