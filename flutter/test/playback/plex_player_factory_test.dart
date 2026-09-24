import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/playback/playback_decision.dart';
import 'package:reelay/playback/plex_player_factory.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

void main() {
  group('directPlayUrl', () {
    test('appends the part key and access token to the server base URL', () {
      const part = PlexPart(id: 1, key: '/library/parts/1/file.mkv');
      expect(
        PlexPlayerFactory.directPlayUrl(_server, part),
        'http://192.168.1.5:32400/library/parts/1/file.mkv?X-Plex-Token=tok123',
      );
    });
  });

  group('transcodeUrl', () {
    test('builds the fixed HLS transcode query exactly, with the given session id', () {
      const decision = Transcode(ratingKey: '100', subtitleStreamId: 5);

      final url = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session');

      expect(
        url,
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
        '&X-Plex-Client-Identifier=client-1'
        '&X-Plex-Token=tok123',
      );
    });

    test('identifies the client so PMS can find a transcode profile', () {
      // Without these PMS logs "Unable to find client profile for device;
      // platform=, platformVersion=, device=" and 400s the request.
      const decision = Transcode(ratingKey: '100');
      final params = Uri.parse(
        PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1'),
      ).queryParameters;
      expect(params['X-Plex-Platform'], isNotEmpty);
      expect(params['X-Plex-Client-Profile-Name'], 'Generic');
      expect(params['X-Plex-Product'], 'Reelay');
      expect(params['X-Plex-Client-Identifier'], 'client-1');
    });

    test('defaults subtitleStreamID to 0 and burns nothing when no subtitle is selected', () {
      const decision = Transcode(ratingKey: '100');
      final url = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session');
      expect(url, contains('&subtitles=none&subtitleStreamID=0&'));
    });

    test('generates a fresh session id per call when none is given', () {
      const decision = Transcode(ratingKey: '100');
      final a = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1');
      final b = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1');
      expect(a, isNot(b));
    });

    test('offsetMs tells Plex where to start encoding, converted to whole seconds', () {
      const decision = Transcode(ratingKey: '100');
      final url = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session', offsetMs: 725400);
      expect(url, contains('&offset=725&'));
    });

    test('offsetMs defaults to 0 when resuming from the start', () {
      const decision = Transcode(ratingKey: '100');
      final url = PlexPlayerFactory.transcodeUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session');
      expect(url, contains('&offset=0&'));
    });
  });

  group('mediaUrl', () {
    test('DirectPlay dispatches to directPlayUrl', () {
      const part = PlexPart(id: 1, key: '/library/parts/1/file.mkv');
      const decision = DirectPlay(part: part);
      expect(PlexPlayerFactory.mediaUrl(_server, decision, 8000, clientIdentifier: 'client-1'), PlexPlayerFactory.directPlayUrl(_server, part));
    });

    test('Transcode dispatches to transcodeUrl', () {
      const decision = Transcode(ratingKey: '100');
      final url = PlexPlayerFactory.mediaUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session');
      expect(url, contains('/video/:/transcode/universal/start.m3u8'));
    });

    test('Transcode forwards offsetMs through to transcodeUrl', () {
      const decision = Transcode(ratingKey: '100');
      final url = PlexPlayerFactory.mediaUrl(_server, decision, 8000, clientIdentifier: 'client-1', sessionId: 'fixed-session', offsetMs: 5000);
      expect(url, contains('&offset=5&'));
    });
  });
}
