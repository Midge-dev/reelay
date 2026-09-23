import '../data/plex/plex_models.dart';

const _subtitleStreamType = 3;
const _burnRequiredSubtitleCodecs = {'pgs', 'vobsub', 'dvdsub'};

sealed class PlaybackDecision {
  const PlaybackDecision();
}

class DirectPlay extends PlaybackDecision {
  final PlexPart part;
  final int? subtitleStreamId;

  const DirectPlay({required this.part, this.subtitleStreamId});
}

class Transcode extends PlaybackDecision {
  final String ratingKey;
  final int? subtitleStreamId;

  const Transcode({required this.ratingKey, this.subtitleStreamId});
}

class SubtitleOption {
  final int? streamId;
  final String label;
  final bool requiresBurn;

  const SubtitleOption({this.streamId, required this.label, required this.requiresBurn});
}

/// Where a chosen subtitle track's actual content lives — the fix for the
/// bug ported verbatim from PlexPlayerFactory.kt's `applySubtitleSelection`
/// (see project_flutter_full_conversion.md): that function only ever set a
/// *language* preference on ExoPlayer's TrackSelectionParameters, never the
/// stream's own id/index, and never handled `PlexStream.key != null`
/// (external/sidecar subtitle files) at all — so with multiple same-language
/// tracks, or any external subtitle, the wrong (or no) track played despite
/// the UI showing the right selection. The Phase 4b player adapter must
/// select by this, not by language string.
sealed class SubtitleSource {
  const SubtitleSource();
}

class NoSubtitle extends SubtitleSource {
  const NoSubtitle();
}

/// Muxed into the media container — select by track index, not language.
class EmbeddedSubtitle extends SubtitleSource {
  final int index;
  final String? languageCode;

  const EmbeddedSubtitle({required this.index, this.languageCode});
}

/// A sidecar file Plex serves at a separate URL — must be attached as its
/// own subtitle source, never inferred from the video container's tracks.
class ExternalSubtitle extends SubtitleSource {
  final String key;
  final String? languageCode;

  const ExternalSubtitle({required this.key, this.languageCode});
}

/// Deviates from Kotlin's `subtitleOptions` in one respect: the
/// `video_player` package has no API at all for selecting a subtitle track
/// muxed into the video container — only an externally-supplied caption
/// file, or one already baked into the video. So unlike Kotlin/ExoPlayer
/// (which can select an embedded text track directly, no transcode
/// needed), every embedded track here is treated as burn-required — same
/// as the bitmap codecs (pgs/vobsub/dvdsub) that needed burning even in
/// Kotlin — trading a transcode (server load, a quality/bitrate hit) for
/// actually being able to show it. External sidecar tracks (`key != null`,
/// fetchable at their own URL as a caption file) never need this.
List<SubtitleOption> subtitleOptions(PlexPart part) {
  final tracks = part.streams
      .where((s) => s.streamType == _subtitleStreamType)
      .map((s) => SubtitleOption(streamId: s.id, label: _subtitleLabel(s), requiresBurn: _requiresBurn(s)))
      .toList();
  return [const SubtitleOption(streamId: null, label: 'Off', requiresBurn: false), ...tracks];
}

String _subtitleLabel(PlexStream stream) {
  final base = stream.language ?? stream.codec?.toUpperCase() ?? 'Unknown';
  final suffix = stream.forced ? ' (Forced)' : (_requiresBurn(stream) ? ' (transcode)' : '');
  return '$base$suffix';
}

/// True for anything `video_player` can't render directly: a bitmap codec
/// (never player-selectable, even in Kotlin) or an embedded track (no
/// player-side track-selection API here, unlike ExoPlayer).
bool _requiresBurn(PlexStream stream) => stream.key == null || _burnRequiredSubtitleCodecs.contains(stream.codec?.toLowerCase());

PlaybackDecision decidePlayback(PlexMovieDetail detail, int? subtitleStreamId, {bool forceBurn = false}) {
  if (detail.media.isEmpty) {
    throw StateError('No playable media found for ${detail.title}');
  }
  final media = detail.media.first;
  if (media.parts.isEmpty) {
    throw StateError('No file found for ${detail.title}');
  }
  final part = media.parts.first;

  PlexStream? chosenStream;
  for (final s in part.streams) {
    if (s.streamType == _subtitleStreamType && s.id == subtitleStreamId) {
      chosenStream = s;
      break;
    }
  }
  final requiresBurn = subtitleStreamId != null && (forceBurn || (chosenStream != null && _requiresBurn(chosenStream)));

  if (requiresBurn) {
    return Transcode(ratingKey: detail.ratingKey, subtitleStreamId: subtitleStreamId);
  }
  return DirectPlay(part: part, subtitleStreamId: subtitleStreamId);
}

/// The subtitle a first press of Play starts with: Plex's remembered one,
/// but only when it doesn't force a transcode — a burn-in is something to
/// opt into from the CC menu, not something a remembered language quietly
/// starts. Shared by the player and the source rows (25, 03d) so "Direct
/// play" on a row is what Play then actually does.
int? firstSubtitleStreamId(PlexMovieDetail detail) {
  final id = defaultSubtitleStreamId(detail);
  if (id == null || detail.media.isEmpty || detail.media.first.parts.isEmpty) return null;
  for (final s in detail.media.first.parts.first.streams) {
    if (s.streamType == _subtitleStreamType && s.id == id) return _requiresBurn(s) ? null : id;
  }
  return null;
}

/// What a first press of Play does with [detail]; see [firstSubtitleStreamId].
PlaybackDecision firstPlaybackDecision(PlexMovieDetail detail, {bool forceBurn = false}) =>
    decidePlayback(detail, firstSubtitleStreamId(detail), forceBurn: forceBurn);

int? defaultSubtitleStreamId(PlexMovieDetail detail) {
  if (detail.media.isEmpty || detail.media.first.parts.isEmpty) return null;
  for (final s in detail.media.first.parts.first.streams) {
    if (s.streamType == _subtitleStreamType && s.selected) return s.id;
  }
  return null;
}

/// Resolves exactly which subtitle source a DirectPlay decision needs
/// attached, replacing the Kotlin bug's language-only guess.
SubtitleSource resolveSubtitleSource(PlexPart part, int? subtitleStreamId) {
  if (subtitleStreamId == null) return const NoSubtitle();

  PlexStream? chosen;
  for (final s in part.streams) {
    if (s.streamType == _subtitleStreamType && s.id == subtitleStreamId) {
      chosen = s;
      break;
    }
  }
  if (chosen == null) return const NoSubtitle();

  if (chosen.key != null) {
    return ExternalSubtitle(key: chosen.key!, languageCode: chosen.languageCode);
  }
  if (chosen.index != null) {
    return EmbeddedSubtitle(index: chosen.index!, languageCode: chosen.languageCode);
  }
  return const NoSubtitle();
}
