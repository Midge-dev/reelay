import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../playback/scrub_previews.dart';
import '../../theme/tokens.dart';

/// One preview frame: the whole image, or the [ScrubFrame.source] tile of
/// a sprite sheet, covering the box (centre-cropped). Over the flat
/// placeholder tone until the image is in — and while the next sheet
/// loads, the last frame stays rather than flashing to empty.
class ScrubPreviewImage extends StatefulWidget {
  const ScrubPreviewImage({super.key, required this.frame});

  final ScrubFrame? frame;

  @override
  State<ScrubPreviewImage> createState() => _ScrubPreviewImageState();
}

class _ScrubPreviewImageState extends State<ScrubPreviewImage> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  ImageInfo? _image;
  Rect? _source;

  /// What's painted: [_image] cut to this frame's tile.
  ScrubFrame? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ScrubPreviewImage old) {
    super.didUpdateWidget(old);
    if (old.frame?.image != widget.frame?.image || old.frame?.source != widget.frame?.source) _resolve();
  }

  void _resolve() {
    final frame = widget.frame;
    if (frame == null) return;
    final stream = frame.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) {
      // Same sheet, another tile: no load, just a new cut. (A build follows
      // both callers, so no setState.)
      _source = frame.source;
      _shown = frame;
      return;
    }
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    void apply() {
      _image = info;
      _source = widget.frame?.source;
      _shown = widget.frame;
    }

    if (synchronousCall) {
      apply();
    } else {
      setState(apply);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image?.image;
    return ColoredBox(
      color: AppColors.surface,
      child: image == null
          ? const SizedBox.expand()
          : CustomPaint(
              size: Size.infinite,
              painter: _FramePainter(image, _source, _shown?.atMs),
            ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image, this.source, this.atMs);

  final ui.Image image;
  final Rect? source;
  final int? atMs;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // A tile past the sheet's edge (a short last sheet) paints nothing.
    final src = (source ?? whole).intersect(whole);
    if (src.isEmpty || size.isEmpty) return;
    // Cover: crop the source to the box's aspect, about its centre.
    final boxAspect = size.width / size.height;
    final srcAspect = src.width / src.height;
    final cropped = srcAspect > boxAspect
        ? Rect.fromCenter(center: src.center, width: src.height * boxAspect, height: src.height)
        : Rect.fromCenter(center: src.center, width: src.width, height: src.width / boxAspect);
    canvas.drawImageRect(image, cropped, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.image != image || old.source != source || old.atMs != atMs;
}
