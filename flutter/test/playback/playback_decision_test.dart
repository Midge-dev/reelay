import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/playback/playback_decision.dart';

MediaPart _partWith(List<MediaStream> streams) => MediaPart(id: '1', key: '/library/parts/1/file.mkv', streams: streams);

MediaDetail _detailWith(MediaPart part) => MediaDetail(
      id: '100',
      title: 'Test Movie',
      media: [MediaVersion(parts: [part])],
    );

void main() {
  group('subtitleOptions', () {
    test('always includes an Off option first, then subtitle streams only', () {
      final part = _partWith([
        const MediaStream(id: 1, kind: StreamKind.audio), // audio, should be excluded
        const MediaStream(id: 2, kind: StreamKind.subtitle, key: '/library/streams/2', language: 'English'),
        const MediaStream(id: 3, kind: StreamKind.subtitle, codec: 'pgs'),
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
        const MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', language: 'English', forced: true),
      ]);

      final options = subtitleOptions(part);

      expect(options[1].label, 'English (Forced)');
    });

    test('an embedded, non-burn-codec track is still offered, but marked as requiring a transcode', () {
      final part = _partWith([
        const MediaStream(id: 1, kind: StreamKind.subtitle, language: 'English', index: 0), // no key, not a burn codec
      ]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].label, 'English (transcode)');
      expect(options[1].requiresBurn, isTrue);
    });

    test('an external sidecar track is included even without a burn-required codec', () {
      final part = _partWith([
        const MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', language: 'English'),
      ]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].label, 'English');
    });

    test('a burn-required embedded track is included even without a key', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, codec: 'vobsub')]);

      final options = subtitleOptions(part);

      expect(options, hasLength(2));
      expect(options[1].requiresBurn, isTrue);
    });
  });

  group('decidePlayback', () {
    test('no subtitle selected -> DirectPlay', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, codec: 'pgs')]);
      final decision = decidePlayback(_detailWith(part), null);
      expect(decision, isA<DirectPlay>());
    });

    test('forceTranscode (direct play already failed) -> Transcode, even with nothing to burn', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', codec: 'srt')]);
      expect(decidePlayback(_detailWith(part), null, forceTranscode: true), isA<Transcode>());
      expect(decidePlayback(_detailWith(part), 1, forceTranscode: true), isA<Transcode>());
    });

    test('external sidecar track selected -> DirectPlay', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', codec: 'srt', language: 'English')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<DirectPlay>());
    });

    test('a WebVTT sidecar selected -> DirectPlay', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', codec: 'vtt')]);
      expect(decidePlayback(_detailWith(part), 1), isA<DirectPlay>());
    });

    test('an ASS/SSA sidecar selected -> Transcode, since video_player would misread it as SubRip', () {
      for (final codec in ['ass', 'ssa']) {
        final part = _partWith([MediaStream(id: 1, kind: StreamKind.subtitle, key: '/library/streams/1', codec: codec)]);
        final decision = decidePlayback(_detailWith(part), 1);
        expect(decision, isA<Transcode>(), reason: codec);
        expect(subtitleOptions(part).last.requiresBurn, isTrue, reason: codec);
      }
    });

    test('embedded soft-subtitle codec (no sidecar key) selected -> Transcode', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, codec: 'srt', language: 'English')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<Transcode>());
    });

    test('burn-required codec (pgs) selected -> Transcode', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, codec: 'pgs')]);
      final decision = decidePlayback(_detailWith(part), 1);
      expect(decision, isA<Transcode>());
      expect((decision as Transcode).subtitleStreamId, 1);
    });

    test('forceBurn=true forces Transcode even for a soft-subtitle codec', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, codec: 'srt')]);
      final decision = decidePlayback(_detailWith(part), 1, forceBurn: true);
      expect(decision, isA<Transcode>());
    });
  });

  group('defaultSubtitleStreamId', () {
    test('returns the id of the stream Plex marked selected', () {
      final part = _partWith([
        const MediaStream(id: 1, kind: StreamKind.subtitle, selected: false),
        const MediaStream(id: 2, kind: StreamKind.subtitle, selected: true),
      ]);
      expect(defaultSubtitleStreamId(_detailWith(part)), 2);
    });

    test('returns null when nothing is selected', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, selected: false)]);
      expect(defaultSubtitleStreamId(_detailWith(part)), isNull);
    });
  });

  group('resolveSubtitleSource selects by stream, never by language', () {
    test('null subtitleStreamId -> NoSubtitle', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle)]);
      expect(resolveSubtitleSource(part, null), isA<NoSubtitle>());
    });

    test('an embedded track (no sidecar key) resolves by index, not language', () {
      final part = _partWith([
        const MediaStream(id: 1, kind: StreamKind.subtitle, index: 2, languageCode: 'eng'),
        const MediaStream(id: 2, kind: StreamKind.subtitle, index: 3, languageCode: 'eng'), // same language, different track
      ]);

      final source = resolveSubtitleSource(part, 2);

      expect(source, isA<EmbeddedSubtitle>());
      expect((source as EmbeddedSubtitle).index, 3);
    });

    test('a sidecar track (key set) resolves as an external source, not an embedded index', () {
      final part = _partWith([
        const MediaStream(id: 5, kind: StreamKind.subtitle, key: '/library/streams/5', languageCode: 'eng', index: 0),
      ]);

      final source = resolveSubtitleSource(part, 5);

      expect(source, isA<ExternalSubtitle>());
      expect((source as ExternalSubtitle).key, '/library/streams/5');
    });

    test('unknown subtitleStreamId -> NoSubtitle', () {
      final part = _partWith([const MediaStream(id: 1, kind: StreamKind.subtitle, index: 0)]);
      expect(resolveSubtitleSource(part, 999), isA<NoSubtitle>());
    });
  });
}
