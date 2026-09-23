import 'plex_models.dart';

class PlexImageUrl {
  PlexImageUrl._();

  static const _tokenParam = 'X-Plex-Token';
  static const _transcodePath = '/photo/:/transcode';

  static String? of(PlexServer server, String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${server.baseUrl}$path?$_tokenParam=${server.accessToken}';
  }

  /// Rewrites a server-local artwork URL built by [of] to go through Plex's
  /// photo transcoder at [width]×[height] device pixels, so the server sends
  /// roughly what is painted rather than the 1000×1500+ master. Anything that
  /// is not a tokenised server path (external CDN art, an already-transcoded
  /// URL, no known size) is returned unchanged.
  static String sized(String url, {int? width, int? height}) {
    if (width == null || height == null) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final token = uri.queryParameters[_tokenParam];
    if (token == null || uri.path == _transcodePath) return url;
    return uri.replace(
      path: _transcodePath,
      queryParameters: {
        'width': '$width',
        'height': '$height',
        'minSize': '1',
        'upscale': '1',
        'url': uri.path,
        _tokenParam: token,
      },
    ).toString();
  }
}
