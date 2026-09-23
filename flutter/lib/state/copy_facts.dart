import '../data/plex/media_facts.dart';
import '../data/plex/plex_models.dart';
import '../playback/playback_decision.dart';

/// What one copy of a title would be to play (screens 03d and 25): the
/// picture and sound, the file, what Play would do with it here, and how
/// far in that server has you.
class CopyFacts {
  final String? picture;
  final String? audio;

  /// "HEVC 34.2 GB".
  final String? file;
  final bool directPlay;
  final int viewOffsetMs;

  /// Higher is better: 4K > 1080p > 720p > SD; 0 when Plex didn't say.
  final int pictureRank;

  const CopyFacts({
    this.picture,
    this.audio,
    this.file,
    required this.directPlay,
    this.viewOffsetMs = 0,
    this.pictureRank = 0,
  });

  factory CopyFacts.of(PlexMovieDetail detail, {bool forceBurn = false}) {
    final media = detail.media.isNotEmpty ? detail.media.first : null;
    final facts = media == null ? null : MediaFacts(media);
    bool direct;
    try {
      direct =
          firstPlaybackDecision(detail, forceBurn: forceBurn) is DirectPlay;
    } catch (_) {
      direct = false;
    }
    return CopyFacts(
      picture: facts?.picture,
      audio: facts?.audio,
      file: facts?.file?.replaceAll(' · ', ' '),
      directPlay: direct,
      viewOffsetMs: detail.viewOffset ?? 0,
      pictureRank: _rank(media?.videoResolution),
    );
  }

  static int _rank(String? resolution) {
    final r = resolution?.toLowerCase();
    if (r == null || r.isEmpty) return 0;
    if (r == '4k') return 2160;
    if (r == 'sd') return 480;
    return int.tryParse(r) ?? 0;
  }
}
