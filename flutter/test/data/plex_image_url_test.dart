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

  group('sized', () {
    const local = 'http://192.168.1.5:32400/library/metadata/1/thumb/1690000000?X-Plex-Token=tok123';

    test('routes a tokenised server path through the photo transcoder', () {
      final uri = Uri.parse(PlexImageUrl.sized(local, width: 448, height: 640));
      expect(uri.origin, 'http://192.168.1.5:32400');
      expect(uri.path, '/photo/:/transcode');
      expect(uri.queryParameters['width'], '448');
      expect(uri.queryParameters['height'], '640');
      expect(uri.queryParameters['url'], '/library/metadata/1/thumb/1690000000');
      expect(uri.queryParameters['X-Plex-Token'], 'tok123');
    });

    test('leaves external, already-transcoded and unsized URLs alone', () {
      const cdn = 'https://cdn.example.com/poster.jpg';
      expect(PlexImageUrl.sized(cdn, width: 448, height: 640), cdn);
      final once = PlexImageUrl.sized(local, width: 448, height: 640);
      expect(PlexImageUrl.sized(once, width: 64, height: 64), once);
      expect(PlexImageUrl.sized(local, width: null, height: 640), local);
    });
  });
}
