import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../focus/dpad_long_press.dart';
import '../theme/scale.dart';
import '../theme/tokens.dart';
import 'content_color.dart';
import 'surface_style.dart';

/// Ports ui/kit/FocusableSurface.kt — the primitive every other kit
/// component (Button, Card, FilterChip, IconButton, ListItem, Switch)
/// funnels through. Resolves container/content color, border and the
/// Nocturne focus signal (fill step, accent hairline, leading spine, 1.03x
/// scale — see DESIGN.md non-negotiable #3) from focus/press/selected/
/// enabled state (precedence: disabled > pressed > focused > selected >
/// default), handles D-pad select as a click (and, if [onLongClick] is
/// set, a held select via [DpadLongPressDetector]) alongside pointer taps.
///
/// The three focus signals are drawn together and never independently —
/// changing one without the others is exactly the drift DESIGN.md warns
/// against. If a screen needs a one-off focusable that can't go through
/// this widget, use [LeadingSpinePainter] directly rather than
/// approximating the signal by hand.
class FocusableSurface extends StatefulWidget {
  final VoidCallback onClick;
  final VoidCallback? onLongClick;
  final bool enabled;
  final bool selected;
  final OutlinedBorder shape;
  final SurfaceColors colors;
  final SurfaceBorder border;
  final FocusNode? focusNode;
  final bool autofocus;
  final AlignmentGeometry contentAlignment;
  final ValueChanged<bool>? onFocusChange;
  final ValueChanged<bool>? onPressChange;
  final Widget child;

  const FocusableSurface({
    super.key,
    required this.onClick,
    this.onLongClick,
    this.enabled = true,
    this.selected = false,
    required this.shape,
    required this.colors,
    this.border = const SurfaceBorder(),
    this.focusNode,
    this.autofocus = false,
    this.contentAlignment = Alignment.center,
    this.onFocusChange,
    this.onPressChange,
    required this.child,
  });

  @override
  State<FocusableSurface> createState() => _FocusableSurfaceState();
}

class _FocusableSurfaceState extends State<FocusableSurface> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _pressed = false;
  DpadLongPressDetector? _longPress;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    if (widget.onLongClick != null) {
      _longPress = DpadLongPressDetector(onLongPress: widget.onLongClick!);
    }
  }

  @override
  void didUpdateWidget(covariant FocusableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onLongClick != oldWidget.onLongClick) {
      _longPress?.dispose();
      _longPress = widget.onLongClick != null
          ? DpadLongPressDetector(onLongPress: widget.onLongClick!)
          : null;
    }
    // A caller that reuses this Element for a different logical item across
    // rebuilds (e.g. a list whose row composition shifts, changing which
    // FocusNode a given position gets) needs this re-synced — otherwise the
    // old node's focus listener (and its possibly-still-true hasFocus)
    // keeps driving this surface's visuals even though a new node was
    // handed in, while the new node's real focus goes unheard here.
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (_ownsFocusNode) _focusNode.dispose();
      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
      _focused = _focusNode.hasFocus;
    }
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    widget.onFocusChange?.call(_focused);
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onPressChange?.call(pressed);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    _longPress?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!DpadLongPressDetector.selectKeys.contains(event.logicalKey))
      return KeyEventResult.ignored;
    if (event is KeyDownEvent) _setPressed(true);
    if (event is KeyUpEvent) _setPressed(false);
    return handleDpadSelect(
      event,
      longPress: _longPress,
      onClick: () {
        if (widget.enabled) widget.onClick();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final border = widget.border;
    final motionFull = AppMotion.level == MotionLevel.full;

    final Color containerColor;
    final Color contentColor;
    final SurfaceBorderSide? activeBorderSide;
    final bool showSpine;
    final Color spineColor;
    var spineWidth = AppShape.spineWidth;
    final double targetScale;
    final List<BoxShadow> shadows;

    if (!widget.enabled) {
      // Disabled ignores focus/press/selection entirely and renders the
      // idle appearance — the whole surface is dimmed to 45% opacity
      // afterwards, rather than this branch picking its own faded colors.
      containerColor = colors.container;
      contentColor = colors.content;
      activeBorderSide = border.idle;
      showSpine = false;
      spineColor = AppColors.transparent;
      targetScale = 1.0;
      shadows = const [];
    } else if (_pressed) {
      // Colour only, no scale change, no spine — DESIGN.md's motion section.
      containerColor = colors.pressedContainer;
      contentColor = colors.pressedContent;
      activeBorderSide = SurfaceBorderSide.solid(
        AppFocusTreatment.pressedBorderColor,
        width: border.idle?.width ?? AppShape.borderWidth,
      );
      showSpine = false;
      spineColor = AppColors.transparent;
      targetScale = 1.0;
      shadows = const [];
    } else if (_focused) {
      containerColor = colors.focusedContainer;
      contentColor = colors.focusedContent;
      activeBorderSide =
          border.focused ??
          SurfaceBorderSide.solid(AppFocusTreatment.focusedBorderColor);
      showSpine = !border.noSpine;
      spineColor = AppFocusTreatment.focusedSpineColor;
      targetScale = motionFull ? AppFocusTreatment.focusScale : 1.0;
      shadows = motionFull ? AppElevation.raised : const [];
    } else if (widget.selected) {
      containerColor = colors.selectedContainer;
      contentColor = colors.selectedContent;
      activeBorderSide = border.idle;
      showSpine = !border.noSpine || border.selectedSpine != null;
      spineColor = border.selectedSpine?.color ?? AppFocusTreatment.selectedSpineColor;
      spineWidth = border.selectedSpine?.width ?? AppShape.spineWidth;
      targetScale = 1.0;
      shadows = const [];
    } else {
      containerColor = colors.container;
      contentColor = colors.content;
      activeBorderSide = border.idle;
      showSpine = false;
      spineColor = AppColors.transparent;
      targetScale = 1.0;
      shadows = const [];
    }

    final duration = _focused ? AppMotion.focusEnter : AppMotion.focusExit;
    final curve = _focused ? AppMotion.enter : AppMotion.exit;

    Widget surface = AnimatedContainer(
      duration: duration,
      curve: curve,
      decoration: ShapeDecoration(
        color: containerColor,
        shape: activeBorderSide != null
            ? widget.shape.copyWith(
                side: BorderSide(
                  color: activeBorderSide.color,
                  width: activeBorderSide.width.du(context),
                ),
              )
            : widget.shape,
        shadows: shadows,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: widget.shape),
        child: ContentColor(
          color: contentColor,
          // Factors of 1: shrink-wrap the content under loose constraints
          // (a button in a Wrap or Row is its content's width, not the
          // row's), while tight constraints (a grid cell, a stretched list
          // row) still size the surface to the slot and align within it.
          child: Align(
            alignment: widget.contentAlignment,
            widthFactor: 1,
            heightFactor: 1,
            child: widget.child,
          ),
        ),
      ),
    );

    if (showSpine) {
      surface = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: spineWidth.du(context)),
        duration: AppMotion.focusSpineWipe,
        curve: AppMotion.enter,
        builder: (context, width, child) => CustomPaint(
          foregroundPainter: LeadingSpinePainter(
            shape: widget.shape,
            color: spineColor,
            width: width,
          ),
          child: child,
        ),
        child: surface,
      );
    }

    if (widget.selected && _focused) {
      surface = Stack(
        fit: StackFit.passthrough,
        children: [
          surface,
          Positioned(
            top: AppSpacing.sm.du(context),
            right: AppSpacing.sm.du(context),
            child: Container(
              width: AppSpacing.md.du(context),
              height: AppSpacing.md.du(context),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      );
    }

    surface = AnimatedScale(
      scale: targetScale,
      duration: duration,
      curve: curve,
      child: surface,
    );

    if (!widget.enabled) {
      surface = Opacity(opacity: 0.45, child: surface);
    }

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled
              ? () {
                  _focusNode.requestFocus();
                  widget.onClick();
                }
              : null,
          onLongPress: widget.enabled ? widget.onLongClick : null,
          child: surface,
        ),
      ),
    );
  }
}

/// The solid leading-edge spine every kit component funnelling through
/// FocusableSurface gets when focused (or, in ink, when selected-but-not-
/// focused) — a flat bar of colour clipped to the surface's own rounded
/// shape, not a soft edge, so it survives a washed-out TV panel. Public so
/// a hand-rolled focusable (one that can't go through FocusableSurface
/// itself) can still match the same signal instead of approximating it.
class LeadingSpinePainter extends CustomPainter {
  final OutlinedBorder shape;
  final Color color;
  final double width;

  LeadingSpinePainter({
    required this.shape,
    required this.color,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0) return;
    final rect = Offset.zero & size;
    final clipPath = shape.getOuterPath(rect);
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, size.height),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LeadingSpinePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.width != width;
}
