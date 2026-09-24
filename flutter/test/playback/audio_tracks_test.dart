import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/playback/audio_tracks.dart';

PlexPart _part(List<PlexStream> streams) => PlexPart(id: 1, key: '/library/parts/1/file.mkv', streams: streams);

const _english = PlexStream(id: 10, streamType: 2, languageCode: 'eng', displayTitle: 'English (TrueHD 7.1)');
const _commentary = PlexStream(id: 11, streamType: 2, languageCode: 'eng', displayTitle: 'English (AAC Stereo)');
const _french = PlexStream(id: 12, streamType: 2, languageCode: 'fre', displayTitle: 'Français (AC3 5.1)', selected: true);

void main() {
  test('lists only audio streams, in container order, with Plex\'s labels', () {
    final options = audioOptions(_part([
      const PlexStream(id: 1, streamType: 1),
      _english,
      const PlexStream(id: 2, streamType: 3, codec: 'srt'),
      _french,
    ]));
    expect(options.map((o) => o.streamId), [10, 12]);
    expect(options.map((o) => o.label), ['English (TrueHD 7.1)', 'Français (AC3 5.1)']);
  });

  test('starts on the track Plex has selected, else the first', () {
    expect(initialAudioStreamId(_part([_english, _french])), 12);
    expect(initialAudioStreamId(_part([_english, _commentary])), 10);
    expect(initialAudioStreamId(_part(const [])), isNull);
  });

  group('playerAudioTrackFor', () {
    final options = audioOptions(_part([_english, _commentary, _french]));

    test('matches by position when the player sees the same number of tracks', () {
      final tracks = [(id: 'a', language: 'en'), (id: 'b', language: 'en'), (id: 'c', language: 'fr')];
      expect(playerAudioTrackFor(options, 11, tracks), 'b', reason: 'two English tracks: language alone cannot tell them apart');
      expect(playerAudioTrackFor(options, 12, tracks), 'c');
    });

    test('falls back to language when the counts differ', () {
      final tracks = [(id: 'a', language: 'en-US'), (id: 'c', language: 'fr')];
      expect(playerAudioTrackFor(options, 12, tracks), 'c');
    });

    test('gives up rather than guess when nothing safely matches', () {
      expect(playerAudioTrackFor(options, 12, [(id: 'a', language: 'de')]), isNull);
      expect(playerAudioTrackFor(options, 99, [(id: 'a', language: 'en')]), isNull);
      expect(playerAudioTrackFor(options, 10, const []), isNull);
    });
  });
}
