import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_server_api.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

void main() {
  test('streamSelectionUrl selects the subtitle on the part itself, across all parts', () {
    expect(
      streamSelectionUrl(_server, 42, subtitleStreamId: 7),
      'http://192.168.1.5:32400/library/parts/42?subtitleStreamID=7&allParts=1',
    );
  });

  test('streamSelectionUrl can select audio and subtitle together', () {
    expect(
      streamSelectionUrl(_server, 42, audioStreamId: 3, subtitleStreamId: 7),
      'http://192.168.1.5:32400/library/parts/42?audioStreamID=3&subtitleStreamID=7&allParts=1',
    );
  });
}
