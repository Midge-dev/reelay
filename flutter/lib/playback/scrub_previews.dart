import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/painting.dart';

/// One preview frame: [image], or the [source] part of it (a tile of a
/// sprite sheet), for the moment [atMs] into the video.
class ScrubFrame {
  final ImageProvider image;

  /// In the image's own pixels; null for the whole image.
  final Rect? source;
  final int atMs;

  const ScrubFrame(this.image, {this.source, required this.atMs});
}

/// Screen 13's preview frames above the focused scrubber, from whichever
/// the server keeps: Plex's BIF index ([BifPreviews]) or Jellyfin's
/// trickplay sheets ([TrickplayPreviews]).
abstract class ScrubPreviews {
  /// The frame at or before [positionMs], or null before the first.
  ScrubFrame? frameAt(int positionMs);
}

/// A BIF file (Roku's "base index frames", what Plex's video preview
/// thumbnails are): a header, an index of (timestamp, offset) pairs ending
/// in 0xFFFFFFFF, then a JPEG per frame. Held whole in memory — a 2-hour
/// film is a few MB.
class BifPreviews implements ScrubPreviews {
  BifPreviews._(this._times, this._images);

  final List<int> _times;
  final List<Uint8List> _images;
  final _providers = <int, MemoryImage>{};

  int get length => _times.length;

  static const _magic = [0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A];

  /// Null when [bytes] isn't a BIF with at least one frame.
  static BifPreviews? parse(Uint8List bytes) {
    if (bytes.length < 64) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(12, Endian.little);
    var multiplier = data.getUint32(16, Endian.little);
    if (multiplier == 0) multiplier = 1000;
    if (bytes.length < 64 + (count + 1) * 8) return null;
    final times = <int>[];
    final images = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final at = 64 + i * 8;
      final start = data.getUint32(at + 4, Endian.little);
      final end = data.getUint32(at + 12, Endian.little);
      if (end <= start || end > bytes.length) continue;
      times.add(data.getUint32(at, Endian.little) * multiplier);
      images.add(Uint8List.sublistView(bytes, start, end));
    }
    return times.isEmpty ? null : BifPreviews._(times, images);
  }

  @override
  ScrubFrame? frameAt(int positionMs) {
    // The last frame at or before positionMs (the index is in time order).
    var lo = 0, hi = _times.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_times[mid] <= positionMs) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return null;
    final image = _providers.putIfAbsent(found, () => MemoryImage(_images[found]));
    return ScrubFrame(image, atMs: _times[found]);
  }
}

/// Jellyfin's trickplay (10.9+): tiles of [tileWidth]×[tileHeight]
/// thumbnails, each [width]×[height] px, one every [intervalMs], laid out
/// row by row across numbered sheets.
class TrickplayPreviews implements ScrubPreviews {
  TrickplayPreviews({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.count,
    required this.intervalMs,
    required this.sheetImage,
  });

  final int width, height, tileWidth, tileHeight, count, intervalMs;

  /// The sheet numbered n.
  final ImageProvider Function(int sheet) sheetImage;
  final _sheets = <int, ImageProvider>{};

  @override
  ScrubFrame? frameAt(int positionMs) {
    if (count <= 0 || intervalMs <= 0 || tileWidth <= 0 || tileHeight <= 0) return null;
    final index = (positionMs ~/ intervalMs).clamp(0, count - 1);
    final perSheet = tileWidth * tileHeight;
    final sheet = index ~/ perSheet;
    final tile = index % perSheet;
    final column = tile % tileWidth;
    final row = tile ~/ tileWidth;
    final image = _sheets.putIfAbsent(sheet, () => sheetImage(sheet));
    return ScrubFrame(
      image,
      source: Rect.fromLTWH(column * width.toDouble(), row * height.toDouble(), width.toDouble(), height.toDouble()),
      atMs: index * intervalMs,
    );
  }
}
