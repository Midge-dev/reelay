import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../focus/dpad_long_press.dart';
import 'content_color.dart';
import 'surface_style.dart';

/// Ports ui/kit/FocusableSurface.kt — the primitive every other kit
/// component (Button, Card, FilterChip, IconButton, ListItem, Switch)
/// funnels through. Resolves container/content color, border, and glow
/// from focus/press/selected/enabled state (precedence: disabled > pressed
/// > focused > selected > default, matching the Kotlin `when` blocks
/// exactly), handles D-pad select as a click (and, if [onLongClick] is
/// set, a held select via [DpadLongPressDetector]) alongside pointer taps.
class FocusableSurface extends StatefulWidget {
  final VoidCallback onClick;
  final VoidCallback? onLongClick;
  final bool enabled;
  final bool selected;
  final OutlinedBorder shape;
  final SurfaceColors colors;
  final SurfaceBorder border;
  final SurfaceGlow glow;
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
    this.glow = const SurfaceGlow(),
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
      _longPress = widget.onLongClick != null ? DpadLongPressDetector(onLongPress: widget.onLongClick!) : null;
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
    if (!DpadLongPressDetector.selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _setPressed(true);
    if (event is KeyUpEvent) _setPressed(false);
    return handleDpadSelect(event, longPress: _longPress, onClick: () {
      if (widget.enabled) widget.onClick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final Color containerColor;
    final Color contentColor;
    if (!widget.enabled) {
      containerColor = colors.disabledContainer;
      contentColor = colors.disabledContent;
    } else if (_pressed) {
      containerColor = colors.pressedContainer;
      contentColor = colors.pressedContent;
    } else if (_focused) {
      containerColor = colors.focusedContainer;
      contentColor = colors.focusedContent;
    } else if (widget.selected) {
      containerColor = colors.selectedContainer;
      contentColor = colors.selectedContent;
    } else {
      containerColor = colors.container;
      contentColor = colors.content;
    }

    final activeBorder = _focused ? widget.border.focused : widget.border.idle;
    final glowColor = _focused ? widget.glow.focusedColor : null;

    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        color: containerColor,
        shape: activeBorder?.color != null
            ? widget.shape.copyWith(side: BorderSide(color: activeBorder!.color!, width: activeBorder.width))
            : widget.shape,
        shadows: glowColor != null
            ? [BoxShadow(color: glowColor.withValues(alpha: widget.glow.alpha), blurRadius: widget.glow.radius * 2)]
            : null,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: widget.shape),
        child: ContentColor(
          color: contentColor,
          child: Align(alignment: widget.contentAlignment, child: widget.child),
        ),
      ),
    );

    if (activeBorder?.gradient != null) {
      surface = CustomPaint(
        foregroundPainter: _GradientBorderPainter(shape: widget.shape, gradient: activeBorder!.gradient!, width: activeBorder.width),
        child: surface,
      );
    }

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.enabled,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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

class _GradientBorderPainter extends CustomPainter {
  final OutlinedBorder shape;
  final Gradient gradient;
  final double width;

  _GradientBorderPainter({required this.shape, required this.gradient, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final insetRect = rect.deflate(width / 2);
    final path = shape.getOuterPath(insetRect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = gradient.createShader(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientBorderPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.gradient != gradient || oldDelegate.width != width;
}
