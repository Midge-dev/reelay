import 'plex_models.dart';

/// Screen 03's media facts, stated plainly — "the people who run their own
/// servers care about them". Each returns null when Plex didn't say.
class MediaFacts {
  final PlexMedia media;

  const MediaFacts(this.media);

  List<PlexStream> get _streams => [for (final p in media.parts) ...p.streams];

  /// "4K HDR", "1080p", "SD".
  String? get picture {
    final r = media.videoResolution?.toLowerCase();
    final base = switch (r) {
      null || '' => null,
      '4k' => '4K',
      'sd' => 'SD',
      _ when int.tryParse(r) != null => '${r}p',
      _ => r.toUpperCase(),
    };
    if (base == null) return null;
    final hdr = _streams.any((s) {
      if (s.streamType != 1) return false;
      final t = s.displayTitle?.toLowerCase() ?? '';
      return t.contains('hdr') ||
          t.contains('dovi') ||
          t.contains('dolby vision');
    });
    return hdr ? '$base HDR' : base;
  }

  /// "TrueHD 7.1", "DD+ 5.1", "AAC Stereo".
  String? get audio {
    final codec = switch (media.audioCodec?.toLowerCase()) {
      null || '' => null,
      'truehd' => 'TrueHD',
      'eac3' => 'DD+',
      'ac3' => 'Dolby Digital',
      'dca' || 'dts' => 'DTS',
      'flac' => 'FLAC',
      'opus' => 'Opus',
      final c => c.toUpperCase(),
    };
    if (codec == null) return null;
    final layout = switch (media.audioChannels) {
      8 => '7.1',
      6 => '5.1',
      2 => 'Stereo',
      1 => 'Mono',
      null => null,
      final n => '$n ch',
    };
    return layout == null ? codec : '$codec $layout';
  }

  /// "HEVC · 34.2 GB".
  String? get file {
    final codec = switch (media.videoCodec?.toLowerCase()) {
      null || '' => null,
      'hevc' || 'h265' => 'HEVC',
      'h264' => 'H.264',
      'av1' => 'AV1',
      'mpeg2video' => 'MPEG-2',
      final c => c.toUpperCase(),
    };
    final bytes = media.parts.fold<int>(0, (sum, p) => sum + (p.size ?? 0));
    final size = bytes > 0 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : null;
    final parts = [?codec, ?size];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "English, Swedish, forced" — at most three languages, then "+N".
  String? get subtitles {
    final subs = _streams.where((s) => s.streamType == 3).toList();
    if (subs.isEmpty) return null;
    final languages = <String>[];
    for (final s in subs) {
      final l = s.language;
      if (l != null && !languages.contains(l)) languages.add(l);
    }
    final shown = languages.take(3).toList();
    if (languages.length > 3) shown.add('+${languages.length - 3}');
    if (subs.any((s) => s.forced)) shown.add('forced');
    return shown.isEmpty ? '${subs.length} tracks' : shown.join(', ');
  }
}
