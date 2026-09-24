import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_server_api.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

void main() {
  test('subtitleSelectionUrl selects the stream on the part itself, across all parts', () {
    expect(
      subtitleSelectionUrl(_server, 42, 7),
      'http://192.168.1.5:32400/library/parts/42?subtitleStreamID=7&allParts=1',
    );
  });
}
