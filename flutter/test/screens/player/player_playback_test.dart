import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_client.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/media/media_server_client.dart';
import 'package:reelay/data/plex/plex_client.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/player/player_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../playback/fake_video_player_platform.dart';

/// Playback as someone with a remote sees it: what opens, from where, with
/// which subtitles, and what the server is told — on both backends.
///
/// The server is a real client's URL building (so the stream URLs are what
/// a real server gets) with the network calls recorded instead of sent.
class _RecordingClient implements MediaServerClient {
  _RecordingClient(this.inner, this.fake, {this.subtitleFiles = const {}});

  final MediaServerClient inner;
  final FakeVideoPlayerPlatform fake;

  /// Sidecar key -> file contents; a key missing here fails to download.
  final Map<String, String> subtitleFiles;

  /// (partId, audio, subtitle, streams opened so far) for each selection.
  final selections = <({String partId, int? audio, int? subtitle, int openedBefore})>[];
  final reports = <({PlaybackReportState state, int timeMs})>[];
  final subtitleFetches = <String>[];

  /// What checkTranscode answers: null to go ahead, else a refusal.
  String? transcodeRefusal;
  final transcodeChecks = <String>[];
  final stoppedTranscodes = <String>[];

  @override
  Future<String?> checkTranscode(String transcodeUrl) async {
    transcodeChecks.add(transcodeUrl);
    return transcodeRefusal;
  }

  @override
  Future<void> stopTranscode(String sessionId) async => stoppedTranscodes.add(sessionId);

  @override
  MediaServer get server => inner.server;
  @override
  String directPlayUrl(MediaPart part) => inner.directPlayUrl(part);
  @override
  String transcodeUrl(
    String itemId, {
    String? partId,
    int? subtitleStreamId,
    int? audioStreamId,
    required int maxVideoBitrateKbps,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  }) => inner.transcodeUrl(
    itemId,
    partId: partId,
    subtitleStreamId: subtitleStreamId,
    audioStreamId: audioStreamId,
    maxVideoBitrateKbps: maxVideoBitrateKbps,
    sessionIdentifier: sessionIdentifier,
    sessionId: sessionId,
    offsetMs: offsetMs,
  );
  @override
  bool get transcodeStartsAtOffset => inner.transcodeStartsAtOffset;
  @override
  String subtitleUrl(String key) => inner.subtitleUrl(key);

  @override
  Future<List<int>> fetchSubtitle(String key) async {
    subtitleFetches.add(key);
    final file = subtitleFiles[key];
    if (file == null) throw StateError('404 $key');
    return file.codeUnits;
  }

  @override
  Future<void> selectStreams(String partId, {int? audioStreamId, int? subtitleStreamId}) async {
    selections.add((partId: partId, audio: audioStreamId, subtitle: subtitleStreamId, openedBefore: fake.openedUris.length));
  }

  @override
  Future<void> reportProgress(
    String itemId,
    PlaybackReportState state, {
    required int timeMs,
    required int durationMs,
    required String sessionIdentifier,
  }) async => reports.add((state: state, timeMs: timeMs));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// One backend's way of doing things, so every test runs on both.
class _Backend {
  const _Backend(this.name, {required this.server, required this.partKey, required this.transcodePath, required this.startsAtOffset});

  final String name;
  final MediaServer server;
  final String partKey;

  /// Every transcode URL contains this; direct play doesn't.
  final String transcodePath;

  /// Plex: a transcode starts at the resume point (`offset=`), never seeked.
  /// Jellyfin: the whole film, seeked like direct play.
  final bool startsAtOffset;

  MediaServerClient client() => switch (server.backend) {
    MediaBackend.plex => PlexClient(server, 'client-1'),
    MediaBackend.jellyfin => JellyfinClient(server, 'client-1'),
  };
}

const _plex = _Backend(
  'Plex',
  server: MediaServer(name: 'Loft', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok'),
  partKey: '/library/parts/1/file.mkv',
  transcodePath: '/video/:/transcode/universal/start.m3u8',
  startsAtOffset: true,
);
const _jellyfin = _Backend(
  'Jellyfin',
  server: MediaServer(backend: MediaBackend.jellyfin, name: 'Den', baseUrl: 'http://192.168.1.6:8096', accessToken: 'tok', userId: 'u1'),
  partKey: '/Videos/1/stream?static=true&MediaSourceId=1',
  transcodePath: '/master.m3u8',
  startsAtOffset: false,
);

const _srt = MediaStream(id: 20, kind: StreamKind.subtitle, codec: 'srt', language: 'English', languageCode: 'eng', key: '/subs/20');
const _pgs = MediaStream(id: 21, kind: StreamKind.subtitle, codec: 'pgs', language: 'English', languageCode: 'eng', index: 3);
const _englishAudio = MediaStream(id: 10, kind: StreamKind.audio, languageCode: 'eng', language: 'English', selected: true);
const _frenchAudio = MediaStream(id: 11, kind: StreamKind.audio, languageCode: 'fre', language: 'Français');

MediaDetail _film(_Backend b, {List<MediaStream> streams = const [], int? viewOffset = 60000, int? duration}) => MediaDetail(
  id: '1',
  title: 'Arrival',
  viewOffset: viewOffset,
  duration: duration,
  media: [
    MediaVersion(parts: [MediaPart(id: '1', key: b.partKey, streams: streams)]),
  ],
);

const _srtFile = '1\n00:01:00,000 --> 00:01:05,000\nWhat is your purpose on Earth?\n\n';

class _Session {
  _Session(this.fake, this.client, this.failures, this.exits, this.bitrates);
  final FakeVideoPlayerPlatform fake;
  final _RecordingClient client;
  final List<(String, int)> failures;
  final List<int> exits;
  final List<int> bitrates;
}

Future<_Session> _open(
  WidgetTester tester,
  _Backend b, {
  required MediaDetail detail,
  FakeVideoPlayerPlatform? fake,
  AppSettings settings = const AppSettings(),
  Map<String, String> subtitleFiles = const {},
  Future<MediaItem?> Function()? loadNextEpisode,
  String? transcodeRefusal,
}) async {
  final platform = fake ?? FakeVideoPlayerPlatform();
  VideoPlayerPlatform.instance = platform;
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = _RecordingClient(b.client(), platform, subtitleFiles: subtitleFiles)..transcodeRefusal = transcodeRefusal;
  final failures = <(String, int)>[];
  final exits = <int>[];
  final bitrates = <int>[];
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          PageRouteBuilder<T>(settings: settings, pageBuilder: (c, _, _) => builder(c)),
      home: PlayerScreen(
        client: client,
        detail: detail,
        settings: settings,
        onBitrateChanged: bitrates.add,
        onExit: () => exits.add(1),
        onFailed: (reason, positionMs) => failures.add((reason, positionMs)),
        loadNextEpisode: loadNextEpisode,
      ),
    ),
  );
  await _settle(tester);
  return _Session(platform, client, failures, exits, bitrates);
}

/// Lets the async open/seek/caption work finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Playback has reached [ms] on the current stream; video_player polls the
/// position every 500ms while playing.
Future<void> _playTo(WidgetTester tester, _Session s, int ms) async {
  s.fake.setPosition(s.fake.latestPlayerId, Duration(milliseconds: ms));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _settle(tester);
}

/// From Play/Pause (where focus starts), along the button row.
Future<void> _pressButton(WidgetTester tester, {required int rightOfPlay}) async {
  await _press(tester, LogicalKeyboardKey.arrowRight, times: rightOfPlay);
  await _press(tester, LogicalKeyboardKey.select);
}

// Rewind, Play/Pause, Forward, Subtitles, Quality, [Chat], Menu.
Future<void> _pressSubtitles(WidgetTester tester) => _pressButton(tester, rightOfPlay: 2);
/// With no subtitle tracks the Subtitles button is disabled and skipped.
Future<void> _pressQuality(WidgetTester tester, {bool subtitles = true}) =>
    _pressButton(tester, rightOfPlay: subtitles ? 3 : 2);

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  for (final b in [_plex, _jellyfin]) {
    group(b.name, () {
      test('backend fixture is what it says', () {
        expect(b.client().transcodeStartsAtOffset, b.startsAtOffset);
      });

      testWidgets('a film with a resume point direct-plays from it', (tester) async {
        final s = await _open(tester, b, detail: _film(b));

        expect(s.fake.openedUris.single, isNot(contains(b.transcodePath)));
        expect(s.fake.seeksByPlayer[0], [60000]);
        expect(s.failures, isEmpty);
        await _close(tester);
      });

      group('subtitles', () {
        testWidgets('a text subtitle file plays over the same stream, and shows at its time', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_srt]), subtitleFiles: {'/subs/20': _srtFile});

          await _pressSubtitles(tester);
          await _playTo(tester, s, 61000);

          expect(s.fake.openedUris, hasLength(1), reason: 'no new stream for a sidecar');
          expect(s.client.subtitleFetches, ['/subs/20']);
          expect(find.text('What is your purpose on Earth?'), findsOneWidget);

          await _playTo(tester, s, 66000);
          expect(find.text('What is your purpose on Earth?'), findsNothing, reason: 'gone after its cue ends');
          await _close(tester);
        });

        testWidgets('a picture subtitle restarts as a transcode with it burned in, from the same spot', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_pgs]));
          await _playTo(tester, s, 90000);

          await _pressSubtitles(tester);

          expect(s.fake.openedUris, hasLength(2));
          final url = s.fake.openedUris.last;
          expect(url, contains(b.transcodePath));
          if (b.startsAtOffset) {
            expect(url, contains('subtitles=burn'));
            expect(url, contains('offset=90&'));
            expect(s.fake.seeksByPlayer[1], isNull, reason: 'a Plex transcode starts at the offset; a seek 400s');
            expect(
              s.client.selections.where((x) => x.subtitle == 21),
              [(partId: '1', audio: null, subtitle: 21, openedBefore: 1)],
              reason: 'Plex burns whatever the part has selected, so it must be told before the stream opens',
            );
          } else {
            expect(url, contains('SubtitleMethod=Encode'));
            expect(s.fake.seeksByPlayer[1], [90000]);
          }
          expect(s.failures, isEmpty);
          await _close(tester);
        });

        testWidgets('turning a burned-in subtitle off goes back to direct play, from the same spot', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_pgs]));
          await _pressSubtitles(tester); // -> PGS, a transcode
          await _playTo(tester, s, 120000);

          await _press(tester, LogicalKeyboardKey.select); // still on Subtitles: -> Off

          expect(s.fake.openedUris, hasLength(3));
          expect(s.fake.openedUris.last, isNot(contains(b.transcodePath)));
          expect(s.fake.seeksByPlayer[2], [120000]);
          await _close(tester);
        });

        testWidgets('the subtitles button steps Off, then each track, then Off again', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_srt, _pgs]), subtitleFiles: {'/subs/20': _srtFile});
          await _pressSubtitles(tester);
          expect(s.fake.openedUris, hasLength(1), reason: 'Off -> the SRT: same stream');
          // Focus stays on the button: Select again moves on.
          await _press(tester, LogicalKeyboardKey.select);
          expect(s.fake.openedUris, hasLength(2), reason: 'SRT -> PGS: a transcode');
          expect(s.fake.openedUris.last, contains(b.transcodePath));
          await _press(tester, LogicalKeyboardKey.select);
          expect(s.fake.openedUris, hasLength(3), reason: 'PGS -> Off: back to direct play');
          expect(s.fake.openedUris.last, isNot(contains(b.transcodePath)));
          await _close(tester);
        });

        testWidgets("a subtitle file that won't download doesn't stop the film", (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_srt]));

          await _pressSubtitles(tester);
          await _playTo(tester, s, 61000);

          expect(s.client.subtitleFetches, ['/subs/20']);
          expect(s.failures, isEmpty);
          expect(s.fake.openedUris, hasLength(1));
          await _close(tester);
        });

        testWidgets("Plex's remembered text subtitle is on from the start; a picture one isn't", (tester) async {
          final withSrt = await _open(
            tester,
            b,
            detail: _film(b, streams: const [MediaStream(id: 20, kind: StreamKind.subtitle, codec: 'srt', language: 'English', key: '/subs/20', selected: true)]),
            subtitleFiles: {'/subs/20': _srtFile},
          );
          await _playTo(tester, withSrt, 61000);
          expect(find.text('What is your purpose on Earth?'), findsOneWidget);
          expect(withSrt.fake.openedUris.single, isNot(contains(b.transcodePath)));
          await _close(tester);

          final withPgs = await _open(
            tester,
            b,
            detail: _film(b, streams: const [MediaStream(id: 21, kind: StreamKind.subtitle, codec: 'pgs', index: 3, selected: true)]),
          );
          // A picture track would mean a transcode before the first frame;
          // it starts direct, and the subtitles button offers it.
          expect(withPgs.fake.openedUris.single, isNot(contains(b.transcodePath)));
          await _close(tester);
        });
      });

      group('every restart picks up where it was', () {
        testWidgets('changing quality on a transcode', (tester) async {
          final s = await _open(
            tester,
            b,
            detail: _film(b, streams: const [_srt]),
            settings: const AppSettings(forceBurnSubtitles: true),
            subtitleFiles: {'/subs/20': _srtFile},
          );
          await _pressSubtitles(tester); // SRT, burned in by the setting: a transcode
          expect(s.fake.openedUris.last, contains(b.transcodePath));
          await _playTo(tester, s, 300000);
          final before = s.fake.openedUris.length;

          await _press(tester, LogicalKeyboardKey.arrowRight); // Subtitles -> Quality
          await _press(tester, LogicalKeyboardKey.select);

          expect(s.bitrates, hasLength(1));
          expect(s.fake.openedUris, hasLength(before + 1));
          final url = s.fake.openedUris.last;
          expect(url, contains(b.transcodePath));
          if (b.startsAtOffset) {
            expect(url, contains('offset=300&'));
            expect(s.fake.seeksByPlayer[s.fake.latestPlayerId], isNull);
          } else {
            expect(s.fake.seeksByPlayer[s.fake.latestPlayerId], [300000]);
          }
          await _close(tester);
        });

        testWidgets('changing quality while direct playing changes nothing', (tester) async {
          final s = await _open(tester, b, detail: _film(b));
          await _pressQuality(tester, subtitles: false);

          expect(s.bitrates, hasLength(1), reason: 'remembered for the next transcode');
          expect(s.fake.openedUris, hasLength(1), reason: 'direct play has no bitrate to change');
          await _close(tester);
        });

        testWidgets('a file this TV cannot play mid-film falls back to a transcode from that spot', (tester) async {
          final s = await _open(tester, b, detail: _film(b));
          await _playTo(tester, s, 754000);

          s.fake.emitError(0);
          await _settle(tester);

          expect(s.fake.openedUris, hasLength(2));
          expect(s.fake.openedUris.last, contains(b.transcodePath));
          if (b.startsAtOffset) {
            expect(s.fake.openedUris.last, contains('offset=754&'));
          } else {
            expect(s.fake.seeksByPlayer[1], [754000]);
          }
          await _close(tester);
        });

        testWidgets('changing audio on a transcode is a new stream with the new track', (tester) async {
          final s = await _open(
            tester,
            b,
            detail: _film(b, streams: const [_englishAudio, _frenchAudio, _pgs]),
          );
          await _pressSubtitles(tester); // PGS: a transcode
          await _playTo(tester, s, 200000);
          final before = s.fake.openedUris.length;

          // The menu's Audio tab: Menu is the last button in the row.
          await _press(tester, LogicalKeyboardKey.arrowRight, times: 2); // Quality, Menu
          await _press(tester, LogicalKeyboardKey.select);
          await tester.tap(find.text('Audio'));
          await _settle(tester);
          await tester.tap(find.text('Français').last);
          await _settle(tester);

          expect(s.fake.openedUris, hasLength(before + 1));
          if (b.startsAtOffset) {
            expect(s.fake.openedUris.last, contains('offset=200&'));
            expect(s.client.selections.last, (partId: '1', audio: 11, subtitle: 21, openedBefore: before));
          } else {
            expect(s.fake.openedUris.last, contains('AudioStreamIndex='));
            expect(s.fake.seeksByPlayer[s.fake.latestPlayerId], [200000]);
          }
          await _close(tester);
        });
      });

      group('the transcode session', () {
        String? sessionOf(String url) => Uri.parse(url).queryParameters['session'];

        testWidgets('every transcode restart reuses one session, so the server replaces the job', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_srt, _pgs]), settings: const AppSettings(forceBurnSubtitles: true));
          await _pressSubtitles(tester); // SRT, burned in: a transcode
          await _press(tester, LogicalKeyboardKey.select); // PGS: another
          await _press(tester, LogicalKeyboardKey.arrowRight); // Quality
          await _press(tester, LogicalKeyboardKey.select); // and another

          final transcodes = s.fake.openedUris.where((u) => u.contains(b.transcodePath)).toList();
          expect(transcodes, hasLength(3));
          if (b.startsAtOffset) {
            expect(transcodes.map(sessionOf).toSet(), hasLength(1), reason: transcodes.join('\n'));
            expect(sessionOf(transcodes.first), isNotNull);
          }
          expect(s.client.stoppedTranscodes, isEmpty, reason: 'replaced in place, not stopped');
          await _close(tester);
        });

        testWidgets('the server is asked before every transcode opens, never before direct play', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_pgs]));
          expect(s.client.transcodeChecks, isEmpty);

          await _pressSubtitles(tester);
          expect(s.client.transcodeChecks, [s.fake.openedUris.last]);
          await _close(tester);
        });

        testWidgets('going back to direct play, or leaving, ends the transcode', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_pgs]));
          await _pressSubtitles(tester); // PGS: a transcode
          final session = Uri.parse(s.fake.openedUris.last).queryParameters['session'];
          await _press(tester, LogicalKeyboardKey.select); // Off: direct play
          expect(s.client.stoppedTranscodes, hasLength(1));
          if (b.startsAtOffset) expect(s.client.stoppedTranscodes.single, session);

          await _press(tester, LogicalKeyboardKey.select); // PGS again
          await _close(tester);
          expect(s.client.stoppedTranscodes, hasLength(2), reason: 'leaving the player mid-transcode');
        });

        testWidgets("leaving a direct play doesn't touch transcodes", (tester) async {
          final s = await _open(tester, b, detail: _film(b));
          await _close(tester);
          expect(s.client.stoppedTranscodes, isEmpty);
        });

        testWidgets("when the server refuses and the stream fails, the error gives the server's reason", (tester) async {
          final s = await _open(
            tester,
            b,
            detail: _film(b, streams: const [_pgs]),
            fake: FakeVideoPlayerPlatform(failInitWhere: (uri) => uri.contains(b.transcodePath)),
            transcodeRefusal: 'Remote stream limit reached',
          );
          await _playTo(tester, s, 90000);
          await _pressSubtitles(tester);

          expect(s.failures, [("${b.server.name} wouldn't transcode this: Remote stream limit reached", 90000)]);
          await _close(tester);
        });

        testWidgets('a refusal never stops a stream the server serves anyway', (tester) async {
          final s = await _open(tester, b, detail: _film(b, streams: const [_pgs]), transcodeRefusal: 'answered 400');
          await _pressSubtitles(tester);

          expect(s.fake.openedUris.last, contains(b.transcodePath));
          expect(s.failures, isEmpty);
          await _close(tester);
        });
      });

      group('what the server hears', () {
        testWidgets('progress every few seconds while playing, paused when paused, stopped on Back', (tester) async {
          final s = await _open(tester, b, detail: _film(b, duration: 6000000));
          await _playTo(tester, s, 70000);
          await tester.pump(const Duration(seconds: 5));
          expect(s.client.reports.last, (state: PlaybackReportState.playing, timeMs: 70000));

          await _press(tester, LogicalKeyboardKey.select); // Play/Pause has focus
          await tester.pump(const Duration(seconds: 5));
          expect(s.client.reports.last.state, PlaybackReportState.paused);

          await tester.binding.handlePopRoute();
          await _settle(tester);
          expect(s.client.reports.last, (state: PlaybackReportState.stopped, timeMs: 70000));
          expect(s.exits, [1]);
          await _close(tester);
        });

        testWidgets('a stream that fails reports stopped, once, where it got to', (tester) async {
          final s = await _open(
            tester,
            b,
            detail: _film(b, streams: const [_pgs]),
          );
          await _pressSubtitles(tester); // a transcode: nothing left to fall back to
          await _playTo(tester, s, 500000);

          s.fake.emitError(s.fake.latestPlayerId);
          await _settle(tester);
          s.fake.emitError(s.fake.latestPlayerId);
          await _settle(tester);

          expect(s.failures, hasLength(1));
          expect(s.failures.single.$2, 500000);
          expect(s.client.reports.where((r) => r.state == PlaybackReportState.stopped), [(state: PlaybackReportState.stopped, timeMs: 500000)]);
          await _close(tester);
        });
      });

      group('Up Next', () {
        const next = MediaItem(id: '2', kind: MediaKind.episode, title: 'The Second', index: 2, parentIndex: 1);

        testWidgets('loads the next episode in the last 40 seconds, once, and Not now dismisses it', (tester) async {
          var loads = 0;
          final s = await _open(
            tester,
            b,
            detail: _film(b, viewOffset: null),
            fake: FakeVideoPlayerPlatform(initialDuration: const Duration(minutes: 40)),
            loadNextEpisode: () async {
              loads++;
              return next;
            },
          );
          await _playTo(tester, s, 39 * 60000 - 45000);
          expect(loads, 0, reason: 'not yet: 45s left');

          await _playTo(tester, s, 39 * 60000 + 30000);
          await _settle(tester);
          expect(loads, 1);
          expect(find.text('The Second'), findsOneWidget);

          await tester.tap(find.text('Not now'));
          await _settle(tester);
          expect(find.text('The Second'), findsNothing);

          await _playTo(tester, s, 39 * 60000 + 40000);
          expect(loads, 1, reason: 'dismissed stays dismissed');
          await _close(tester);
        });
      });
    });
  }
}
