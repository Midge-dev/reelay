import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A surface's colours per state, named SurfaceColors (not `Colors`) to
/// avoid colliding with Flutter's own Material `Colors` class if it's ever
/// imported alongside this. Unset states fall back: focused -> container, pressed -> focused -> container,
/// selected -> container independently. Disabled is not a color state
/// here — FocusableSurface renders the idle appearance at 45% opacity for
/// the whole surface instead, per AppFocusTreatment / tokens.json's
/// `focus.disabled`.
class SurfaceColors {
  final Color container;
  final Color content;
  final Color focusedContainer;
  final Color focusedContent;
  final Color pressedContainer;
  final Color pressedContent;
  final Color selectedContainer;
  final Color selectedContent;

  SurfaceColors({
    required this.container,
    required this.content,
    Color? focusedContainer,
    Color? focusedContent,
    Color? pressedContainer,
    Color? pressedContent,
    Color? selectedContainer,
    Color? selectedContent,
  })  : focusedContainer = focusedContainer ?? container,
        focusedContent = focusedContent ?? content,
        pressedContainer = pressedContainer ?? focusedContainer ?? container,
        pressedContent = pressedContent ?? focusedContent ?? content,
        selectedContainer = selectedContainer ?? container,
        selectedContent = selectedContent ?? content;
}

/// A single solid border stroke. The old gradient-border variant is gone —
/// Nocturne's focus signal is a flat accent hairline plus a leading spine,
/// never a gradient (see AppFocusTreatment / FocusableSurface).
class SurfaceBorderSide {
  final double width;
  final Color color;

  const SurfaceBorderSide.solid(this.color, {this.width = AppShape.borderWidth});
}

/// A surface's border per state, with [noSpine]
/// for the two Nocturne cases where the leading spine is dropped and the
/// hairline (which already runs all the way round any shape) is left to
/// carry focus alone: poster/still cards, where a spine would cover the
/// artwork — pass a wider [focused] width (AppShape.artFrameWidth) there —
/// and 62x62 icon-only buttons, where a spine would eat a quarter of the
/// square. Everywhere else, focus is fill step + hairline + spine together,
/// never a subset — see DESIGN.md non-negotiable #3.
class SurfaceBorder {
  final SurfaceBorderSide? idle;
  final SurfaceBorderSide? focused;
  final bool noSpine;

  /// Overrides the selected-not-focused spine (default: 6 du in
  /// [AppFocusTreatment.selectedSpineColor]). The rail's active item is the
  /// one user — screens 01-25 draw it as a 4 du accent spine on a raised
  /// fill, marking "where you are" in the accent rather than ink.
  final SurfaceBorderSide? selectedSpine;

  const SurfaceBorder({this.idle, this.focused, this.noSpine = false, this.selectedSpine});
}
