import '../plex/plex_image_url.dart';
import 'media_server.dart';

/// Artwork URLs for any backend — what screens call with a thumb/art value
/// and the server it came from.
class ArtworkUrl {
  ArtworkUrl._();

  /// A full URL for [path] (a thumb/art value from [server]'s items), or
  /// null when there's none.
  static String? of(MediaServer server, String? path) => switch (server.backend) {
    MediaBackend.plex => PlexImageUrl.of(server, path),
    MediaBackend.jellyfin => null,
  };

  /// Asks the server for roughly [width]×[height] device pixels instead of
  /// the full-size master, where the URL is one it can resize. Anything
  /// else comes back unchanged.
  static String sized(String url, {int? width, int? height}) => PlexImageUrl.sized(url, width: width, height: height);
}
