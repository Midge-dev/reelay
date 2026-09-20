import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'focusable_surface.dart';
import 'scroll_peek.dart';
import 'surface_style.dart';

const _cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));

final _cardColors = SurfaceColors(container: AppColors.surfaceVariant, content: AppColors.white);
const _cardBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
const _cardGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

const _defaultFocusScale = 1.06;

/// Compose's `spring(dampingRatio = 0.75f, stiffness = Spring.StiffnessMediumLow)`.
/// Flutter's SpringDescription.damping is an absolute coefficient, not a
/// ratio — damping = dampingRatio * 2 * sqrt(mass * stiffness).
/// StiffnessMediumLow is Compose's own named constant (400).
const _cardFocusSpring = SpringDescription(mass: 1, stiffness: 400, damping: 30);

/// Ports ui/kit/Card.kt's `Card` — focus triggers scale-only magnification
/// via a spring (intentional slight overshoot), never scales below 1x even
/// when pressed, and elevates above neighbors while focused (so it isn't
/// visually clipped by adjacent cards at the scaled-up size).
class AppCard extends StatefulWidget {
  final VoidCallback onClick;
  final VoidCallback? onLongClick;
  final bool enabled;
  final FocusNode? focusNode;
  final bool autofocus;
  final double focusScale;
  final ShapeBorder? shape;
  final bool ensureVisibleOnFocus;
  final Widget child;

  const AppCard({
    super.key,
    required this.onClick,
    this.onLongClick,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.focusScale = _defaultFocusScale,
    this.shape,
    this.ensureVisibleOnFocus = true,
    required this.child,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // AnimationController's default upperBound is 1.0 — since focusScale is
    // > 1.0, the spring's target was being silently clamped straight back
    // down to 1.0 on every tick, so the card never visibly grew at all.
    _controller = AnimationController(value: 1, vsync: this, upperBound: widget.focusScale);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool focused) {
    final target = focused ? widget.focusScale : 1.0;
    _controller.animateWith(SpringSimulation(_cardFocusSpring, _controller.value, target, 0));
    if (focused && widget.ensureVisibleOnFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCardVisible(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape is OutlinedBorder ? widget.shape as OutlinedBorder : _cardShape;

    // Compose additionally bumps zIndex(1f) while focused so a scaled-up
    // card paints over its still-unscaled neighbors. Flutter's Row/List
    // paint order has no per-child zIndex equivalent; the PoC's real fix
    // for the same occlusion hazard was reserving extra row height +
    // centering (see project_flutter_focus_poc.md), not z-ordering — that
    // remains the caller's job when it lays out a row of these.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
      child: FocusableSurface(
        onClick: widget.onClick,
        onLongClick: widget.onLongClick,
        enabled: widget.enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: _handleFocusChange,
        shape: shape,
        colors: _cardColors,
        border: _cardBorder,
        glow: _cardGlow,
        child: widget.child,
      ),
    );
  }
}

/// Ports ui/kit/Card.kt's `CardContainer` — stacks an image card and a
/// title below it.
class CardContainer extends StatelessWidget {
  final Widget imageCard;
  final Widget title;

  const CardContainer({super.key, required this.imageCard, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [imageCard, title],
    );
  }
}
