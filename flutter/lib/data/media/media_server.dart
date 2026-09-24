/// Which kind of media server a [MediaServer] is. Everything above
/// `data/` works in the neutral types of this directory; only the client
/// for a backend (see media_server_client.dart) knows its wire format.
enum MediaBackend {
  plex('Plex'),
  jellyfin('Jellyfin');

  const MediaBackend(this.label);

  /// How the backend is named in copy — "Plex · Local".
  final String label;
}

/// One connected media server, of either backend.
class MediaServer {
  final MediaBackend backend;
  final String name;
  final String baseUrl;
  final String accessToken;

  /// Stable per-server id — Plex's `machineIdentifier`, Jellyfin's
  /// `ServerId` — which survives IP/URL changes, unlike [baseUrl]. Empty for
  /// servers built without one (e.g. older test fixtures); the multi-server
  /// hub keys connected/disabled servers by it, so real connections always
  /// set it.
  final String id;

  /// The signed-in user on this server, for backends whose API paths name
  /// one (Jellyfin). Null for Plex, whose token already implies the user.
  final String? userId;

  const MediaServer({
    this.backend = MediaBackend.plex,
    required this.name,
    required this.baseUrl,
    required this.accessToken,
    this.id = '',
    this.userId,
  });
}

/// Which path a server was actually reached through — screen 06 of the
/// Nocturne handoff calls this Local/Relayed/Unreachable.
enum ServerReachability { local, relayed, unreachable }

class ReachableServer {
  final MediaServer server;
  final ServerReachability reachability;

  const ReachableServer(this.server, this.reachability);
}
