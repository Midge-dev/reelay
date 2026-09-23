import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../theme/tokens.dart';

/// A poster, still or backdrop over its placeholder tone. The placeholder is
/// a flat [AppColors.surface] fill — the handoff's "neutral placeholder
/// tone" — and the image fades up over it in [AppMotion.artworkFade] once
/// decoded (cut instead of faded below [MotionLevel.noStagger]). Nothing
/// here animates while the image is in flight: a row of forty loading
/// posters costs forty flat fills, not forty tickers (DESIGN.md #4).
///
/// The image is requested and decoded at the size it is painted — painted
/// logical px × devicePixelRatio — rather than at the server's full master
/// resolution (handoff README, "Request artwork at the size it is painted").
/// On failure the placeholder simply stays; no error glyph.
class Artwork extends StatelessWidget {
  final String? imageUrl;

  const Artwork({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = ColoredBox(color: AppColors.surface);
    if (url == null) return SizedBox.expand(child: placeholder);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final width = _bucket(constraints.maxWidth * dpr);
        final height = _bucket(constraints.maxHeight * dpr);
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            Image(
              image: _sizedProvider(url, width, height),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || !AppMotion.crossfadeArtwork) {
                  return frame == null ? const SizedBox.shrink() : child;
                }
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: AppMotion.artworkFade,
                  curve: AppMotion.enter,
                  child: child,
                );
              },
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  /// Rounds a decode target up to the next 64px so near-identical card
  /// sizes (a focused card's layout doesn't change, but rows and grids
  /// differ by a few px) share one cache entry instead of each re-decoding.
  static int? _bucket(double px) {
    if (!px.isFinite || px <= 0) return null;
    return ((px / 64).ceil() * 64).clamp(64, 4096);
  }

  static ImageProvider _sizedProvider(String url, int? width, int? height) {
    final provider = NetworkImage(PlexImageUrl.sized(url, width: width, height: height));
    // Decode no larger than painted even if the server ignores the resize
    // (non-Plex URLs, or an old server without the transcoder). Width only,
    // so the decoder keeps the source's aspect ratio for BoxFit.cover.
    return ResizeImage.resizeIfNeeded(width, null, provider);
  }
}
