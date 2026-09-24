import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/playback/playback_decision.dart';

PlexPart _partWith(List<PlexStream> streams) => PlexPart(id: 1, key: '/library/parts/1/file.mkv', streams: streams);

PlexMovieDetail _detailWith(PlexPart part) => PlexMovieDetail(
      ratingKey: '100',
      title: 'Test Movie',
      media: [PlexMedia(parts: [part])],
    );

void main() {
  group('subtitleOptions', () {
    test('always includes an Off option first, then subtitle streams only', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 2), // audio, should be excluded
        const PlexStream(id: 2, streamType: 3, key: '/library/streams/2', language: 'English'),
        const PlexStream(id: 3, streamType: 3, codec: 'pgs'),
      ]);

      final options = subtitleOptions(part);

      expect(options, hasLength(3));
      expect(options[0].streamId, isNull);
      expect(options[0].label, 'Off');
      expect(options[1].label, 'English');
      expect(options[1].requiresBurn, isFalse);
      expect(options[2].label, 'PGS (transcode)');
      expect(options[2].requiresBurn, isTrue);
    });

    test('forced tracks are labeled distinctly from burn-required ones', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 3, key: '/library/streams/1', language: 'English', forced: true),
      ]);

      final options = subtitleOptions(part);

      expect(options[1].label, 'English (Forced)');
    });

    test('an embedded, non-burn-codec track is still offered, but marked as requiring a transcode', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 3, language: 'English', index: 0), // no key, not a burn codec
      ]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].label, 'English (transcode)');
      expect(options[1].requiresBurn, isTrue);
    });

    test('an external sidecar track is included even without a burn-required codec', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 3, key: '/library/streams/1', language: 'English'),
      ]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].label, 'English');
    });

    test('a burn-required embedded track is included even without a key', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, codec: 'vobsub')]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].requiresBurn, isTrue);
    });
  });

  group('decidePlayback', () {
    test('no subtitle selected -> DirectPlay', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, codec: 'pgs')]);
      final decision = decidePlayback(_detailWith(part), null);
      expect(decision, isA<DirectPlay>());
    });

    test('forceTranscode (direct play already failed) -> Transcode, even with nothing to burn', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, key: '/library/streams/1', codec: 'srt')]);
      expect(decidePlayback(_detailWith(part), null, forceTranscode: true), isA<Transcode>());
      expect(decidePlayback(_detailWith(part), 1, forceTranscode: true), isA<Transcode>());
    });

    test('external sidecar track selected -> DirectPlay', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, key: '/library/streams/1', codec: 'srt', language: 'English')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<DirectPlay>());
    });

    test('a WebVTT sidecar selected -> DirectPlay', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, key: '/library/streams/1', codec: 'vtt')]);
      expect(decidePlayback(_detailWith(part), 1), isA<DirectPlay>());
    });

    test('an ASS/SSA sidecar selected -> Transcode, since video_player would misread it as SubRip', () {
      for (final codec in ['ass', 'ssa']) {
        final part = _partWith([PlexStream(id: 1, streamType: 3, key: '/library/streams/1', codec: codec)]);
        final decision = decidePlayback(_detailWith(part), 1);
        expect(decision, isA<Transcode>(), reason: codec);
        expect(subtitleOptions(part).last.requiresBurn, isTrue, reason: codec);
      }
    });

    test('embedded soft-subtitle codec (no sidecar key) selected -> Transcode', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, codec: 'srt', language: 'English')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<Transcode>());
    });

    test('burn-required codec (pgs) selected -> Transcode', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, codec: 'pgs')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<Transcode>());
      expect((decision as Transcode).subtitleStreamId, 1);
    });

    test('forceBurn=true forces Transcode even for a soft-subtitle codec', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, codec: 'srt')]);
      final decision = decidePlayback(_detailWith(part), 1, forceBurn: true);
      expect(decision, isA<Transcode>());
    });
  });

  group('defaultSubtitleStreamId', () {
    test('returns the id of the stream Plex marked selected', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 3, selected: false),
        const PlexStream(id: 2, streamType: 3, selected: true),
      ]);
      expect(defaultSubtitleStreamId(_detailWith(part)), 2);
    });

    test('returns null when nothing is selected', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, selected: false)]);
      expect(defaultSubtitleStreamId(_detailWith(part)), isNull);
    });
  });

  group('resolveSubtitleSource selects by stream, never by language', () {
    test('null subtitleStreamId -> NoSubtitle', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3)]);
      expect(resolveSubtitleSource(part, null), isA<NoSubtitle>());
    });

    test('an embedded track (no sidecar key) resolves by index, not language', () {
      final part = _partWith([
        const PlexStream(id: 1, streamType: 3, index: 2, languageCode: 'eng'),
        const PlexStream(id: 2, streamType: 3, index: 3, languageCode: 'eng'), // same language, different track
      ]);

      final source = resolveSubtitleSource(part, 2);

      expect(source, isA<EmbeddedSubtitle>());
      expect((source as EmbeddedSubtitle).index, 3);
    });

    test('a sidecar track (key set) resolves as an external source, not an embedded index', () {
      final part = _partWith([
        const PlexStream(id: 5, streamType: 3, key: '/library/streams/5', languageCode: 'eng', index: 0),
      ]);

      final source = resolveSubtitleSource(part, 5);

      expect(source, isA<ExternalSubtitle>());
      expect((source as ExternalSubtitle).key, '/library/streams/5');
    });

    test('unknown subtitleStreamId -> NoSubtitle', () {
      final part = _partWith([const PlexStream(id: 1, streamType: 3, index: 0)]);
      expect(resolveSubtitleSource(part, 999), isA<NoSubtitle>());
    });
  });
}
