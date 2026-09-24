import 'package:flutter/services.dart';

import '../data/plex/plex_models.dart';

const _videoStreamType = 1;
const _channel = MethodChannel('reelay/display');

/// The TV-side half of "Match frame rate" (MainActivity/FrameRateMatcher).
/// Every call is best effort: on a platform without the channel (macOS dev
/// runs, tests) or a TV that won't switch, playback just starts as it is.
class DisplayMode {
  const DisplayMode._();

  /// Whoever asked last. Up Next mounts the next episode's player before the
  /// old one is disposed, so the old one's [clear] must not undo the new
  /// one's request.
  static Object? _owner;

  /// Switch the display to suit [part]'s video stream, returning once the
  /// TV has settled on the new mode (or immediately, if there's nothing to
  /// switch). Capped so a platform that never answers can't hold up
  /// playback.
  static Future<void> matchFrameRate(PlexPart part, {required Object owner}) async {
    _owner = owner;
    final video = part.streams.where((s) => s.streamType == _videoStreamType).firstOrNull;
    final fps = video?.frameRate;
    if (fps == null || fps <= 0) {
      // Nothing to match, but a previous film's mode may still be held.
      try {
        await _channel.invokeMethod<void>('clearFrameRate');
      } catch (_) {}
      return;
    }
    try {
      await _channel
          .invokeMethod<bool>('matchFrameRate', {'fps': fps, 'width': video!.width ?? 0, 'height': video.height ?? 0})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // MissingPluginException off Android, a timeout, or a platform error.
    }
  }

  /// Hand the display mode back to the system, unless someone newer than
  /// [owner] has asked for one since.
  static Future<void> clear({required Object owner}) async {
    if (!identical(_owner, owner)) return;
    _owner = null;
    try {
      await _channel.invokeMethod<void>('clearFrameRate');
    } catch (_) {}
  }
}
