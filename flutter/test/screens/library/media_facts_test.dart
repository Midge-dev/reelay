import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/media_facts.dart';

void main() {
  test('states a 4K HDR TrueHD 7.1 HEVC file as screen 03 writes it', () {
    const media = PlexMedia(
      videoResolution: '4k',
      videoCodec: 'hevc',
      audioCodec: 'truehd',
      audioChannels: 8,
      parts: [
        PlexPart(id: 1, key: '/p', size: 34200000000, streams: [
          PlexStream(streamType: 1, displayTitle: '4K DoVi/HDR10 (HEVC Main 10)'),
          PlexStream(streamType: 3, language: 'English'),
          PlexStream(streamType: 3, language: 'Swedish'),
          PlexStream(streamType: 3, language: 'English', forced: true),
        ]),
      ],
    );
    const facts = MediaFacts(media);
    expect(facts.picture, '4K HDR');
    expect(facts.audio, 'TrueHD 7.1');
    expect(facts.file, 'HEVC · 34.2 GB');
    expect(facts.subtitles, 'English, Swedish, forced');
  });

  test('plain 1080p stereo AAC, no subtitles', () {
    const facts = MediaFacts(PlexMedia(videoResolution: '1080', videoCodec: 'h264', audioCodec: 'aac', audioChannels: 2));
    expect(facts.picture, '1080p');
    expect(facts.audio, 'AAC Stereo');
    expect(facts.file, 'H.264');
    expect(facts.subtitles, isNull);
  });
}
