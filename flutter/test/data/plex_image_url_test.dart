import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_image_url.dart';
import 'package:reelay/data/plex/plex_models.dart';

void main() {
  const server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

  test('returns null for a null or blank path', () {
    expect(PlexImageUrl.of(server, null), isNull);
    expect(PlexImageUrl.of(server, '   '), isNull);
  });

  test('passes an already-absolute URL through unchanged', () {
    expect(PlexImageUrl.of(server, 'https://cdn.example.com/poster.jpg'), 'https://cdn.example.com/poster.jpg');
  });

  test('appends the server base URL and token to a relative path', () {
    expect(
      PlexImageUrl.of(server, '/library/metadata/1/thumb'),
      'http://192.168.1.5:32400/library/metadata/1/thumb?X-Plex-Token=tok123',
    );
  });
}
