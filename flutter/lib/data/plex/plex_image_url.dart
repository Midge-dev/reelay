import 'plex_models.dart';

class PlexImageUrl {
  PlexImageUrl._();

  static String? of(PlexServer server, String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${server.baseUrl}$path?X-Plex-Token=${server.accessToken}';
  }
}
