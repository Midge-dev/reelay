import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../theme/scale.dart';
import '../../theme/tokens.dart';

// Splash spec (design_handoff_reelay_splash/DESIGN.md) — every number below
// is from its §2 geometry and §4 timeline, in du at the 1920×1080 reference.
const _introMs = 1300;
const _breatheHalfMs = 900; // 0.24 → 0.07 → 0.24 is one 1800 ms period
const _exitMs = 300;
const _breatheFromMs = 1600;
const _minHoldMs = 2400;
const _reducedFadeMs = 300;

const _glowPeak = 0.24;
const _glowTrough = 0.07;

/// The first thing Reelay paints: the mark draws itself (~1.2 s), holds
/// while the app loads underneath, then fades to reveal it. Exits when
/// [ready] completes or at 2.4 s, whichever is later — never early (a
/// half-drawn mark reads as a glitch), never held longer than it has to.
/// Still loading at 1.6 s, the glow breathes; the bars never move again.
class SplashScreen extends StatefulWidget {
  final Future<void> ready;
  final VoidCallback onDone;

  const SplashScreen({super.key, required this.ready, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _introMs),
  );
  late final _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _breatheHalfMs),
  );
  late final _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _exitMs),
  );

  Animation<double> _interval(double begin, double end, Curve curve) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: curve),
      );

  late final _ground = _interval(0.000, 0.185, Curves.linear);
  late final _accentBar = _interval(0.123, 0.554, Curves.easeOutQuint);
  late final _inkBar = _interval(0.246, 0.646, Curves.easeOutQuint);
  late final _glow = _interval(0.462, 1.000, Curves.easeOut);
  late final _word = _interval(0.538, 0.923, Curves.easeOutQuint);
  late final _breatheCurve = CurvedAnimation(
    parent: _breathe,
    curve: Curves.easeInOut,
  );

  bool _started = false;
  bool _reducedMotion = false;
  bool _isReady = false;
  Timer? _breatheTimer;
  Timer? _holdTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _run();
  }

  Future<void> _run() async {
    if (_reducedMotion) {
      // Bars and wordmark at full size; the lockup and glow fade in over
      // 300 ms linear instead (see build). No breathe.
      _intro.value = 1;
    } else {
      _intro.forward();
      _breatheTimer = Timer(const Duration(milliseconds: _breatheFromMs), () {
        if (mounted && !_isReady) _breathe.repeat(reverse: true);
      });
    }
    widget.ready.then((_) => _isReady = true, onError: (_) => _isReady = true);

    final held = Completer<void>();
    _holdTimer = Timer(const Duration(milliseconds: _minHoldMs), held.complete);
    await Future.wait([widget.ready.catchError((_) {}), held.future]);
    if (!mounted) return;
    // Let the current breath finish on its 0.24 peak (≤ 900 ms), then exit.
    if (_breathe.isAnimating) {
      await _breathe.animateBack(0);
      if (!mounted) return;
    }
    await _exit.forward();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _breatheTimer?.cancel();
    _holdTimer?.cancel();
    _intro.dispose();
    _breathe.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget lockup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Mark(
          accentBar: _accentBar,
          inkBar: _inkBar,
          glow: _glow,
          breathe: _breatheCurve,
          reducedMotion: _reducedMotion,
        ),
        SizedBox(width: 34.du(context)),
        _Wordmark(progress: _word),
      ],
    );
    if (_reducedMotion) {
      lockup = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: _reducedFadeMs),
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: lockup,
      );
    }
    return FadeTransition(
      // Exit: lockup and ground together, 1 → 0, easeIn — the app is
      // already painted underneath. No slide, scale or route transition.
      opacity: ReverseAnimation(
        CurvedAnimation(parent: _exit, curve: Curves.easeIn),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Frame 0 is the saved theme's canvas — the same colour the
          // native window was (within a few % luminance).
          ColoredBox(color: AppColors.canvas),
          FadeTransition(
            opacity: _ground,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  // CSS radial-gradient(110% 90% at 50% 45%, …): an
                  // ellipse, so scale a circle to the box's aspect.
                  center: const Alignment(0, -0.1),
                  radius: 0.9,
                  transform: const _EllipseTransform(),
                  colors: [
                    AppColors.surface,
                    AppColors.background,
                    AppColors.canvas,
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
          Center(child: lockup),
        ],
      ),
    );
  }
}

/// CSS `radial-gradient(110% 90% at 50% 45%)`: an ellipse whose radii are
/// 110% of the width and 90% of the height. [RadialGradient]'s circle has
/// radius 0.9 × the shorter side (the height, on a TV), so stretch x about
/// the centre until it reaches 1.1 × the width.
class _EllipseTransform extends GradientTransform {
  const _EllipseTransform();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final ry = 0.9 * bounds.shortestSide;
    final sx = (1.1 * bounds.width) / ry;
    final sy = (0.9 * bounds.height) / ry;
    final cx = bounds.left + bounds.width * 0.5;
    final cy = bounds.top + bounds.height * 0.45;
    return Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }
}

/// The 46-unit master mark (rect 36×12 r4 over rect 22×12 r4, gap 4)
/// scaled by 3: 108×36 accent over 66×36 ink, gap 12, both r12, in a
/// 108×84 box — with the accent glow behind it.
class _Mark extends StatelessWidget {
  final Animation<double> accentBar;
  final Animation<double> inkBar;
  final Animation<double> glow;
  final Animation<double> breathe;
  final bool reducedMotion;

  const _Mark({
    required this.accentBar,
    required this.inkBar,
    required this.glow,
    required this.breathe,
    required this.reducedMotion,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(Animation<double> scaleX, double width, Color color) =>
        AnimatedBuilder(
          animation: scaleX,
          builder: (context, child) => Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.diagonal3Values(scaleX.value, 1, 1),
            child: child,
          ),
          child: Container(
            width: width.du(context),
            height: 36.du(context),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12.du(context)),
            ),
          ),
        );

    return SizedBox(
      width: 108.du(context),
      height: 84.du(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The only blurred layer. ImageFiltered, not a BoxShadow — a
          // shadow has an edge; the glow shouldn't.
          Positioned(
            left: -48.du(context),
            top: -44.du(context),
            width: 204.du(context),
            height: 124.du(context),
            child: AnimatedBuilder(
              animation: Listenable.merge([glow, breathe]),
              builder: (context, child) {
                final breath = reducedMotion ? 0.0 : breathe.value;
                final level = _glowPeak - (_glowPeak - _glowTrough) * breath;
                return Opacity(opacity: glow.value * level, child: child);
              },
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 26.du(context),
                  sigmaY: 26.du(context),
                  tileMode: TileMode.decal,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(62.du(context)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: bar(accentBar, 108, AppColors.accent),
          ),
          Positioned(
            left: 0,
            top: 48.du(context),
            child: bar(inkBar, 66, AppColors.splashInkBar),
          ),
        ],
      ),
    );
  }
}

/// "Reelay", Inter 500 at 100 du, line-height 1.0, −3% tracking — text,
/// not a bitmap, so it stays crisp at any scale. Fades in while sliding
/// 14 du from the left.
class _Wordmark extends StatelessWidget {
  final Animation<double> progress;

  const _Wordmark({required this.progress});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Opacity(
        opacity: progress.value,
        child: Transform.translate(
          offset: Offset((1 - progress.value) * -14.du(context), 0),
          child: child,
        ),
      ),
      child: Text(
        'Reelay',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 100.du(context),
          fontWeight: FontWeight.w500,
          height: 1.0,
          letterSpacing: -3.du(context),
          color: AppColors.ink,
        ),
      ),
    );
  }
}
