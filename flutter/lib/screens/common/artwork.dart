import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

const _frameHoldMs = 333;
const _rollDurationMs = 2800;
const _rollBarHeightFraction = 0.34;
const _breatheHalfCycleMs = 1200;
const _crossfadeMs = 220;
const _scanlinePeriodPx = 3.0;

const _placeholderBase = Color(0xFF101015);
final _vignetteColor = AppColors.accent.withValues(alpha: 0.22);
final _rollBarColor = AppColors.accentGlow.withValues(alpha: 0.11);
final _scanlineColor = AppColors.scrim.withValues(alpha: 0.22);

const _noiseFrameAssets = [
  'assets/images/static_noise_1.jpg',
  'assets/images/static_noise_2.jpg',
  'assets/images/static_noise_3.jpg',
  'assets/images/static_noise_4.jpg',
  'assets/images/static_noise_5.jpg',
  'assets/images/static_noise_6.jpg',
];

/// Ports ui/common/Artwork.kt — shows the design system's "lost signal"
/// placeholder (cycling static-noise frames, scanlines, a diagonal roll bar,
/// per-card stagger) while the image is in flight, crossfading to the real
/// artwork once it lands. On failure the grain simply stops — no error
/// glyph, no retry affordance; whatever the card's own idle background is
/// shows through with just its title.
///
/// @param noiseOpacity ceiling for the placeholder's grain layer — 0.5 for a
///   single poster/still, 0.4 in a 5-across grid (per spec, so a whole grid
///   never strobes together), 0.3 for a full-bleed backdrop that sits under
///   its own text scrim.
/// @param staggerDelayMs offsets the roll-bar's phase — pass `index * 120`
///   in a grid/row so cards don't pulse in unison; 0 elsewhere.
class Artwork extends StatelessWidget {
  final String? imageUrl;
  final int staggerDelayMs;
  final double noiseOpacity;

  const Artwork({super.key, this.imageUrl, this.staggerDelayMs = 0, this.noiseOpacity = 0.4});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return _PosterPlaceholder(noiseOpacity: noiseOpacity, staggerDelayMs: staggerDelayMs);

    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => AnimatedSwitcher(
        duration: const Duration(milliseconds: _crossfadeMs),
        // Default layoutBuilder wraps children in a loose Stack, which lets
        // the Image auto-size to preserve its own aspect ratio instead of
        // filling the box tightly — defeating BoxFit.cover whenever the box
        // aspect ratio doesn't already match the image's (e.g. a 16:9 card
        // showing a 2:3 poster). Force tight fill instead.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        child: progress == null
            ? KeyedSubtree(key: const ValueKey('loaded'), child: child)
            : _PosterPlaceholder(key: const ValueKey('loading'), noiseOpacity: noiseOpacity, staggerDelayMs: staggerDelayMs),
      ),
      // No error glyph/retry affordance by design — the grain just stops
      // and whatever's behind this card (its idle background, its title)
      // shows through.
      errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
    );
  }
}

class _PosterPlaceholder extends StatefulWidget {
  final double noiseOpacity;
  final int staggerDelayMs;

  const _PosterPlaceholder({super.key, required this.noiseOpacity, required this.staggerDelayMs});

  @override
  State<_PosterPlaceholder> createState() => _PosterPlaceholderState();
}

class _PosterPlaceholderState extends State<_PosterPlaceholder> with TickerProviderStateMixin {
  final _random = Random();
  late int _frameIndex = _random.nextInt(_noiseFrameAssets.length);
  late final Timer _frameTimer;
  late final AnimationController _breatheController;
  late final Animation<double> _breatheAnimation;
  late final AnimationController _rollController;

  @override
  void initState() {
    super.initState();
    _frameTimer = Timer.periodic(const Duration(milliseconds: _frameHoldMs), (_) {
      if (mounted) setState(() => _frameIndex = _random.nextInt(_noiseFrameAssets.length));
    });
    _breatheController = AnimationController(duration: const Duration(milliseconds: _breatheHalfCycleMs), vsync: this)
      ..repeat(reverse: true);
    _breatheAnimation = Tween<double>(begin: widget.noiseOpacity * 0.6, end: widget.noiseOpacity)
        .animate(CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut));
    // Staggers the roll bar's phase so cards in the same row/grid don't
    // pulse in unison — starts partway through the cycle rather than at 0.
    final startFraction = (widget.staggerDelayMs % _rollDurationMs) / _rollDurationMs;
    _rollController = AnimationController(duration: const Duration(milliseconds: _rollDurationMs), vsync: this)
      ..forward(from: startFraction)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _rollController.forward(from: 0);
      });
  }

  @override
  void dispose() {
    _frameTimer.cancel();
    _breatheController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _placeholderBase,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _breatheAnimation,
              builder: (context, child) => Opacity(opacity: _breatheAnimation.value, child: child),
              child: Image.asset(_noiseFrameAssets[_frameIndex], key: ValueKey(_frameIndex), fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: RadialGradient(colors: [_vignetteColor, AppColors.transparent], radius: 0.9)),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _rollController,
              builder: (context, _) => CustomPaint(painter: _RollBarPainter(progress: _rollController.value)),
            ),
          ),
          const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _ScanlinePainter()))),
        ],
      ),
    );
  }
}

class _RollBarPainter extends CustomPainter {
  final double progress;

  const _RollBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height * _rollBarHeightFraction;
    final barTop = progress * (size.height + barHeight * 1.8) - barHeight * 0.4;
    final rect = Rect.fromLTWH(0, barTop, size.width, barHeight);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.transparent, _rollBarColor, AppColors.transparent],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _RollBarPainter oldDelegate) => oldDelegate.progress != progress;
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _scanlineColor;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
      y += _scanlinePeriodPx;
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => false;
}
