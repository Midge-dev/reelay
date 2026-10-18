import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/media/media_server_client.dart';
import 'package:reelay/data/plex/plex_client.dart';
import 'package:reelay/data/plex/plex_playback_urls.dart';
import 'package:reelay/playback/playback_decision.dart';

const _server = MediaServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

void main() {
  group('plexDirectPlayUrl', () {
    test('appends the part key and access token to the server base URL', () {
      const part = MediaPart(id: '1', key: '/library/parts/1/file.mkv');
      expect(plexDirectPlayUrl(_server, part), 'http://192.168.1.5:32400/library/parts/1/file.mkv?X-Plex-Token=tok123');
    });
  });

  group('plexTranscodeUrl', () {
    String transcode({int? subtitleStreamId, String? sessionId = 'fixed-session', int offsetMs = 0}) => plexTranscodeUrl(
      _server,
      '100',
      subtitleStreamId: subtitleStreamId,
      maxVideoBitrateKbps: 8000,
      clientIdentifier: 'client-1',
      sessionIdentifier: 'play-1',
      sessionId: sessionId,
      offsetMs: offsetMs,
    );

    test('builds the fixed HLS transcode query exactly, with the given session id', () {
      expect(
        transcode(subtitleStreamId: 5),
        'http://192.168.1.5:32400/video/:/transcode/universal/start.m3u8'
        '?path=http%3A%2F%2F192.168.1.5%3A32400%2Flibrary%2Fmetadata%2F100'
        '&mediaIndex=0&partIndex=0&protocol=hls'
        '&fastSeek=1&copyts=1&offset=0'
        '&directPlay=0&directStream=0'
        '&videoResolution=1920x1080&maxVideoBitrate=8000'
        '&subtitleSize=100'
        '&subtitles=burn'
        '&subtitleStreamID=5'
        '&session=fixed-session'
        '&X-Plex-Product=Reelay'
        '&X-Plex-Platform=Android'
        '&X-Plex-Client-Profile-Name=Generic'
        '&X-Plex-Client-Profile-Extra=add-transcode-target(type%3DvideoProfile%26context%3Dstreaming'
        '%26protocol%3Dhls%26container%3Dmpegts%26videoCodec%3Dh264%26audioCodec%3Daac%252Cac3%252Ceac3)'
        '&X-Plex-Client-Identifier=client-1'
        '&X-Plex-Session-Identifier=play-1'
        '&X-Plex-Token=tok123',
      );
    });

    test('identifies the client so PMS can find a transcode profile', () {
      // Without these PMS logs "Unable to find client profile for device;
      // platform=, platformVersion=, device=" and 400s the request.
      final params = Uri.parse(transcode(sessionId: null)).queryParameters;
      expect(params['X-Plex-Platform'], isNotEmpty);
      expect(params['X-Plex-Client-Profile-Name'], 'Generic');
      // Generic names no transcode targets; without one PMS 400s the start
      // request (decision code 4005). What we can play must ride along.
      expect(params['X-Plex-Client-Profile-Extra'], plexTranscodeProfileExtra);
      final target = Uri.splitQueryString(
        RegExp(r'add-transcode-target\((.*)\)').firstMatch(plexTranscodeProfileExtra)!.group(1)!,
      );
      expect(target, {
        'type': 'videoProfile',
        'context': 'streaming',
        'protocol': 'hls',
        'container': 'mpegts',
        'videoCodec': 'h264',
        'audioCodec': 'aac,ac3,eac3',
      });
      expect(params['X-Plex-Product'], 'Reelay');
      expect(params['X-Plex-Client-Identifier'], 'client-1');
      expect(params['X-Plex-Session-Identifier'], 'play-1');
    });

    test('defaults subtitleStreamID to 0 and burns nothing when no subtitle is selected', () {
      expect(transcode(), contains('&subtitles=none&subtitleStreamID=0&'));
    });

    test('generates a fresh session id per call when none is given', () {
      expect(transcode(sessionId: null), isNot(transcode(sessionId: null)));
    });

    test('offsetMs tells Plex where to start encoding, converted to whole seconds', () {
      expect(transcode(offsetMs: 725400), contains('&offset=725&'));
    });
  });

  group('mediaUrl through a PlexClient', () {
    final client = PlexClient(_server, 'client-1');

    test('DirectPlay plays the file itself', () {
      const part = MediaPart(id: '1', key: '/library/parts/1/file.mkv');
      expect(
        mediaUrl(client, const DirectPlay(part: part), 8000, sessionIdentifier: 'play-1'),
        plexDirectPlayUrl(_server, part),
      );
    });

    test('Transcode forwards the item, subtitle and offset', () {
      final url = mediaUrl(
        client,
        const Transcode(itemId: '100', subtitleStreamId: 7),
        8000,
        sessionIdentifier: 'play-1',
        sessionId: 'fixed-session',
        offsetMs: 5000,
      );
      expect(url, contains('/video/:/transcode/universal/start.m3u8'));
      expect(url, contains('%2Flibrary%2Fmetadata%2F100'));
      expect(url, contains('&offset=5&'));
      expect(url, contains('&subtitleStreamID=7&'));
    });
  });

  group('streamSelectionUrl', () {
    test('selects the subtitle on the part itself, across all parts', () {
      expect(
        streamSelectionUrl(_server, '42', subtitleStreamId: 7),
        'http://192.168.1.5:32400/library/parts/42?subtitleStreamID=7&allParts=1',
      );
    });

    test('can select audio and subtitle together', () {
      expect(
        streamSelectionUrl(_server, '42', audioStreamId: 3, subtitleStreamId: 7),
        'http://192.168.1.5:32400/library/parts/42?audioStreamID=3&subtitleStreamID=7&allParts=1',
      );
    });
  });

  group('timeline reports', () {
    test('builds the fixed timeline-report query exactly', () {
      expect(
        timelineReportUrl(_server, '100', 'playing', 5000, 60000),
        'http://192.168.1.5:32400/:/timeline'
        '?ratingKey=100'
        '&key=%2Flibrary%2Fmetadata%2F100'
        '&identifier=com.plexapp.plugins.library'
        '&state=playing'
        '&time=5000'
        '&duration=60000',
      );
    });

    test("carry the playback's session identifier, so PMS ties them to the stream", () {
      final headers = timelineReportHeaders(_server, 'client-id', 'play-1');
      expect(headers['X-Plex-Session-Identifier'], 'play-1');
      expect(headers['X-Plex-Client-Identifier'], 'client-id');
      expect(headers['X-Plex-Token'], 'tok123');
    });

    test('reportProgress never throws even if the request fails (fire-and-forget)', () async {
      // No real server at this address — the request will fail; the report
      // must swallow it.
      final client = PlexClient(const MediaServer(name: 'x', baseUrl: 'http://127.0.0.1:1', accessToken: 't'), 'client-id');
      await expectLater(
        client.reportProgress('1', PlaybackReportState.playing, timeMs: 0, durationMs: 1000, sessionIdentifier: 'play-1'),
        completes,
      );
    });
  });
}
