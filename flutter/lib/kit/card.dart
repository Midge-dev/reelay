import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'scroll_peek.dart';
import 'surface_style.dart';

RoundedRectangleBorder _cardShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
);

SurfaceColors get _cardColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _cardBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// A focusable card. Focus is the standard Nocturne signal —
/// fill step, hairline, leading spine, 1.03x scale, no bounce — via
/// FocusableSurface; nothing card-specific left to layer on top of it. Use
/// [border]/[colors] overrides (or build a dedicated component) for cards
/// that sit on artwork, which take a frame instead of a spine — see
/// DESIGN.md non-negotiable #3 and `SurfaceBorder.noSpine`.
class AppCard extends StatelessWidget {
  final VoidCallback onClick;
  final VoidCallback? onLongClick;
  final bool enabled;
  final bool selected;
  final FocusNode? focusNode;
  final bool autofocus;
  final ShapeBorder? shape;
  final SurfaceColors? colors;
  // Nullable rather than defaulting to _cardBorder directly: that default
  // would need to be a compile-time constant, which it can no longer be
  // now that AppColors is theme-swappable at runtime (see AppColors'
  // own doc comment). Resolved to _cardBorder in build() when omitted.
  final SurfaceBorder? border;
  final bool ensureVisibleOnFocus;
  final ValueChanged<bool>? onFocusChange;
  final Widget child;

  const AppCard({
    super.key,
    required this.onClick,
    this.onLongClick,
    this.enabled = true,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
    this.shape,
    this.colors,
    this.border,
    this.ensureVisibleOnFocus = true,
    this.onFocusChange,
    required this.child,
  });

  void _handleFocusChange(BuildContext context, bool focused) {
    if (focused && ensureVisibleOnFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ensureCardVisible(context);
      });
    }
    onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final outlinedShape = shape is OutlinedBorder
        ? shape as OutlinedBorder
        : _cardShape(context);

    return FocusableSurface(
      onClick: onClick,
      onLongClick: onLongClick,
      enabled: enabled,
      selected: selected,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: (focused) => _handleFocusChange(context, focused),
      shape: outlinedShape,
      colors: colors ?? _cardColors,
      border: border ?? _cardBorder,
      child: child,
    );
  }
}

/// Stacks an image card and a
/// title below it.
class CardContainer extends StatelessWidget {
  final Widget imageCard;
  final Widget title;

  const CardContainer({
    super.key,
    required this.imageCard,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [imageCard, title],
    );
  }
}
