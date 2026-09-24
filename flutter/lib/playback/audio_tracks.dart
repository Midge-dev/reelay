import '../data/plex/plex_models.dart';

const _audioStreamType = 2;

class AudioOption {
  final int streamId;
  final String label;
  final String? languageCode;

  const AudioOption({required this.streamId, required this.label, this.languageCode});
}

/// The part's audio tracks in container order — Plex's own labels
/// ("English (AC3 5.1)"), which say more than the player's would.
List<AudioOption> audioOptions(PlexPart part) => [
  for (final s in part.streams.where((s) => s.streamType == _audioStreamType))
    AudioOption(
      streamId: s.id,
      label: s.displayTitle ?? s.language ?? s.codec?.toUpperCase() ?? 'Track ${s.id}',
      languageCode: s.languageCode,
    ),
];

/// The track Plex has remembered for this part (what Plex Web last picked,
/// or the file's default), else the first.
int? initialAudioStreamId(PlexPart part) {
  final audio = part.streams.where((s) => s.streamType == _audioStreamType).toList();
  if (audio.isEmpty) return null;
  return (audio.firstWhere((s) => s.selected, orElse: () => audio.first)).id;
}

/// An audio track as the player reports it while direct-playing.
typedef PlayerAudioTrack = ({String id, String? language});

/// Which of the player's own audio tracks is Plex's [streamId]. The player
/// and Plex both list a file's audio in container order, so with the same
/// count it's positional; otherwise fall back to the first track in the
/// same language. Null when there's no safe match — better to leave the
/// player's choice alone than switch to the wrong track.
String? playerAudioTrackFor(List<AudioOption> options, int streamId, List<PlayerAudioTrack> tracks) {
  final index = options.indexWhere((o) => o.streamId == streamId);
  if (index < 0 || tracks.isEmpty) return null;
  if (tracks.length == options.length) return tracks[index].id;
  final language = _base(options[index].languageCode);
  if (language == null) return null;
  for (final t in tracks) {
    if (_base(t.language) == language) return t.id;
  }
  return null;
}

// Plex reports ISO 639-2 ("eng"), ExoPlayer usually 639-1 ("en") or a
// BCP 47 tag ("en-US"); compare on the first two letters. Imperfect for a
// handful of languages, but only used when positional matching can't be.
String? _base(String? code) {
  if (code == null || code.length < 2 || code == 'und') return null;
  return code.substring(0, 2).toLowerCase();
}
