import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Where a hold-to-act surface says it's being held — its
/// DpadLongPressDetector.holding — for the [HoldFeedback] inside it.
class HoldScope extends InheritedNotifier<ValueNotifier<bool>> {
  const HoldScope({super.key, required ValueNotifier<bool> holding, required super.child}) : super(notifier: holding);

  static ValueNotifier<bool>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HoldScope>()?.notifier;
}

/// Screen 21's hold: over the [AppMotion.hold] it takes to act, the poster
/// desaturates and draws in [AppMotion.holdDrawIn], "so the gesture is
/// visibly doing something before it fires. Releasing early restores it."
///
/// Wraps the artwork only, never the whole card: the focus signal around it
/// (DESIGN.md #3) keeps its colour and its scale. Linear both ways —
/// AppMotion.exit's curve, since the card is on its way out — and it moves
/// only while the button is held (#4).
class HoldFeedback extends StatefulWidget {
  final Widget child;

  const HoldFeedback({super.key, required this.child});

  @visibleForTesting
  static const transformKey = ValueKey('hold-feedback-transform');
  @visibleForTesting
  static const filterKey = ValueKey('hold-feedback-filter');

  /// The saturation a [ColorFiltered] built here applies (1 = full colour).
  @visibleForTesting
  static double saturationOf(ColorFiltered filtered) {
    // In _saturation's matrix the red channel's own weight is
    // _r + (1 - _r) * s, so s = (m[0] - _r) / (1 - _r).
    final matrix = _matrixOf(filtered.colorFilter);
    return ((matrix[0] - _r) / (1 - _r)).clamp(0.0, 1.0);
  }

  @override
  State<HoldFeedback> createState() => _HoldFeedbackState();
}

// Rec. 709 luma weights.
const _r = 0.2126, _g = 0.7152, _b = 0.0722;

List<double> _saturation(double s) {
  final t = 1 - s;
  return [
    _r * t + s, _g * t, _b * t, 0, 0, //
    _r * t, _g * t + s, _b * t, 0, 0, //
    _r * t, _g * t, _b * t + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

final _matrices = Expando<List<double>>();

List<double> _matrixOf(ColorFilter filter) => _matrices[filter]!;

ColorFilter _filterFor(double saturation) {
  final matrix = _saturation(saturation);
  final filter = ColorFilter.matrix(matrix);
  _matrices[filter] = matrix;
  return filter;
}

class _HoldFeedbackState extends State<HoldFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: AppMotion.hold,
    reverseDuration: AppMotion.press,
  );
  ValueNotifier<bool>? _holding;

  /// Keeps the artwork's own state (its fade-in) as the filter comes and
  /// goes around it — without it, a hold would replay the poster's fade.
  final _childKey = GlobalKey(debugLabel: 'hold-feedback-child');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final holding = HoldScope.maybeOf(context);
    if (holding == _holding) return;
    _holding?.removeListener(_follow);
    _holding = holding?..addListener(_follow);
    _follow();
  }

  void _follow() {
    if (_holding?.value ?? false) {
      _hold.forward();
    } else {
      _hold.reverse();
    }
  }

  @override
  void dispose() {
    _holding?.removeListener(_follow);
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outside a hold-to-act surface, and at rest, nothing extra: a filter
    // layer on every card in a grid costs frames on a Shield.
    if (_holding == null) return widget.child;
    return AnimatedBuilder(
      animation: _hold,
      builder: (context, child) {
        final t = _hold.value;
        if (t == 0) return child!;
        return Transform.scale(
          key: HoldFeedback.transformKey,
          scale: 1 - AppMotion.holdDrawIn * t,
          child: ColorFiltered(
            key: HoldFeedback.filterKey,
            colorFilter: _filterFor(1 - t),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: _childKey, child: widget.child),
    );
  }
}
