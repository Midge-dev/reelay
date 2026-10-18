import '../media/media_server.dart';

/// Jellyfin artwork. Items carry image paths like
/// `/Items/<id>/Images/Primary?tag=<tag>` (see jellyfin_mappers.dart); the
/// tag changes whenever the image does, so a cached copy is never stale.
/// Images are served without a token.
class JellyfinImageUrl {
  JellyfinImageUrl._();

  static String? of(MediaServer server, String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${server.baseUrl}$path';
  }

  /// Whether [url] is a Jellyfin item image that [sized] can resize.
  static bool isImageUrl(String url) =>
      Uri.tryParse(url)?.path.contains('/Images/') ?? false;

  /// Asks Jellyfin for an image that covers [width]×[height] device pixels
  /// (keeping its aspect) rather than the full-size master. Anything else,
  /// or no known size, comes back unchanged.
  static String sized(String url, {int? width, int? height}) {
    if (width == null || height == null || !isImageUrl(url)) return url;
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('fillWidth')) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'fillWidth': '$width',
            'fillHeight': '$height',
            'quality': '90',
          },
        )
        .toString();
  }
}
