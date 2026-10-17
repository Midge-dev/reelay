import '../jellyfin/jellyfin_client.dart';
import '../plex/plex_client.dart';
import 'media_models.dart';
import 'media_server.dart';

/// The playback state a progress report carries.
enum PlaybackReportState { playing, paused, stopped }

/// Everything the app asks of one server, in neutral types. One
/// implementation per [MediaBackend]; build one with [forServer].
///
/// Methods throw on network/server failure — callers that fan out across
/// servers catch per server, so one dead server never blocks another.
abstract class MediaServerClient {
  MediaServer get server;

  /// [clientIdentifier] is this install's stable device id.
  factory MediaServerClient.forServer(MediaServer server, String clientIdentifier) => switch (server.backend) {
    MediaBackend.plex => PlexClient(server, clientIdentifier),
    MediaBackend.jellyfin => JellyfinClient(server, server.clientId ?? clientIdentifier),
  };

  // ---- Browsing ----

  /// The movie and show libraries worth putting on the rail.
  Future<List<MediaLibrary>> fetchLibraries();
  Future<List<MediaItem>> fetchLibraryItems(String libraryId);
  Future<List<MediaItem>> fetchCollections(String libraryId);
  Future<List<MediaItem>> fetchCollectionItems(String collectionId);
  Future<List<MediaItem>> fetchSeasons(String showId);
  Future<List<MediaItem>> fetchEpisodes(String seasonId);

  /// Throws [StateError] when the title is gone from the server.
  Future<MediaDetail> fetchDetail(String id);
  Future<List<MediaHub>> fetchRelatedHubs(String id);

  /// Global search (screen 05): movies, shows and episodes, ungrouped.
  Future<List<MediaItem>> search(String query);

  // ---- People ----

  /// Everything [personId] (this server's id) is credited on, across every
  /// library. Characters and jobs come from each title's own detail.
  Future<List<MediaItem>> fetchPersonMedia(String personId);

  /// People matching [name] on this server, each with this server's id and,
  /// where the backend has one, a [Person.globalId].
  Future<List<Person>> searchPeople(String name);

  /// This server's copies of a work known by [guid] — a watchlist entry's.
  Future<List<MediaItem>> findByGuid(String guid);

  // ---- Home ----

  Future<List<MediaItem>> fetchContinueWatching();
  Future<List<MediaItem>> fetchRecentlyAdded();
  Future<List<MediaItem>> fetchRecentActivity();
  Future<List<MediaItem>> fetchSuggestions();

  /// The episode to play next for a show: where you are, else S1 E1.
  Future<MediaItem?> fetchNextEpisodeForShow(String showId);
  Future<void> removeFromContinueWatching(String id);

  // ---- Artwork ----

  /// A full URL for a thumb/art value from this server's items, or null.
  String? imageUrl(String? path);

  // ---- Playback ----

  String directPlayUrl(MediaPart part);

  /// A server-side transcode of [itemId]'s [partId] file, burning
  /// [subtitleStreamId] in when set, with [audioStreamId] as its one audio
  /// track (Plex reads both from [selectStreams] instead). [sessionIdentifier]
  /// ties it to this playback's progress reports.
  ///
  /// Where it starts depends on the backend — see [transcodeStartsAtOffset].
  String transcodeUrl(
    String itemId, {
    String? partId,
    int? subtitleStreamId,
    int? audioStreamId,
    required int maxVideoBitrateKbps,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  });

  /// True when a transcode begins [offsetMs] into the file and must not be
  /// seeked to it again (Plex: the stream only exists from there). False
  /// when it's the whole film and the player seeks, as for direct play
  /// (Jellyfin publishes a playlist for the full runtime).
  bool get transcodeStartsAtOffset;

  /// The caption file for a sidecar [MediaStream.key].
  String subtitleUrl(String key);

  /// Makes these tracks the file's selection server-side, for backends
  /// whose transcoder reads it from there (Plex). A no-op for the rest.
  Future<void> selectStreams(String partId, {int? audioStreamId, int? subtitleStreamId});

  /// Fire-and-forget progress report; never throws.
  Future<void> reportProgress(
    String itemId,
    PlaybackReportState state, {
    required int timeMs,
    required int durationMs,
    required String sessionIdentifier,
  });
}
