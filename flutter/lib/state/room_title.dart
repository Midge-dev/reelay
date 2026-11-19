import 'package:collection/collection.dart';

import '../data/media/media_models.dart';
import '../data/media/media_server.dart';
import '../data/media/media_server_client.dart';
import '../playback/next_episode.dart';
import '../sync/episode_switch.dart';
import '../sync/relay_protocol.dart';

/// What a Watch Together room advertises for its title: every id another
/// server could know it by — Plex's own guid and the provider ids.
List<String> roomIdsFor(MediaDetail detail) =>
    {?detail.guid, ...detail.externalIds}.toList();

/// Whether [item] is the work [ids] name (see [roomIdsFor]).
bool sharesProviderId(MediaItem item, Set<String> ids) =>
    (item.guid != null && ids.contains(item.guid)) ||
    item.externalIds.any(ids.contains);

/// A room's title on this hub: the host's own item when we share its
/// server, else our copy of the same work on any server, Plex or Jellyfin,
/// found by its title and matched on provider ids — the item id means
/// nothing elsewhere. A room from a host (or relay) that predates server
/// ids carries only the item id, tried on every server as before.
Future<(MediaServer, MediaDetail)?> resolveRoomTitle(
  List<ReachableServer> servers,
  RelayRoomSummary room,
  MediaServerClient Function(MediaServer) clientFor,
) async {
  Future<(MediaServer, MediaDetail)?> detailOn(
    MediaServer server,
    String id,
  ) async {
    try {
      return (server, await clientFor(server).fetchDetail(id));
    } catch (_) {
      return null;
    }
  }

  Future<(MediaServer, MediaDetail)?> firstOf(
    Iterable<Future<(MediaServer, MediaDetail)?>> lookups,
  ) async =>
      (await Future.wait(lookups))
          .whereType<(MediaServer, MediaDetail)>()
          .firstOrNull;

  final ratingKey = room.ratingKey;
  final hostServerId = room.serverId;
  if (hostServerId == null) {
    if (ratingKey == null) return null;
    return firstOf(servers.map((cs) => detailOn(cs.server, ratingKey)));
  }
  final shared = servers.where((s) => s.server.id == hostServerId).firstOrNull;
  if (shared != null && ratingKey != null) {
    final found = await detailOn(shared.server, ratingKey);
    if (found != null) return found;
  }
  final ids = room.ids.toSet();
  final query = room.mediaTitle;
  if (ids.isEmpty || query == null) return null;
  return firstOf(
    servers.map((cs) async {
      try {
        final match = (await clientFor(cs.server).search(query))
            .firstWhereOrNull((item) => sharesProviderId(item, ids));
        return match == null ? null : await detailOn(cs.server, match.id);
      } catch (_) {
        return null;
      }
    }),
  );
}

/// Where a guest plays the episode a room has moved on to ([EpisodeSwitch]),
/// best match first:
///
/// 1. the host's own item, when this hub shares the host's server;
/// 2. the same season and episode of the show this guest is already
///    watching ([currentShowId] on [currentServer]) — its own copy;
/// 3. the show found by title on any server, matched on its provider ids,
///    then that season and episode;
/// 4. the episode itself found by title, matched on its provider ids.
Future<(MediaServer, MediaDetail)?> resolveEpisodeSwitch(
  List<ReachableServer> servers,
  EpisodeSwitch to,
  MediaServerClient Function(MediaServer) clientFor, {
  MediaServer? currentServer,
  String? currentShowId,
}) async {
  Future<(MediaServer, MediaDetail)?> detailOn(MediaServer server, String id) async {
    try {
      return (server, await clientFor(server).fetchDetail(id));
    } catch (_) {
      return null;
    }
  }

  Future<(MediaServer, MediaDetail)?> numberedOn(MediaServer server, String showId) async {
    try {
      final episode = await episodeNumbered(clientFor(server), showId, season: to.seasonIndex, episode: to.episodeIndex);
      return episode == null ? null : await detailOn(server, episode.id);
    } catch (_) {
      return null;
    }
  }

  final shared = servers.where((s) => s.server.id == to.serverId).firstOrNull;
  if (shared != null) {
    final found = await detailOn(shared.server, to.ratingKey);
    if (found != null) return found;
  }
  if (currentServer != null && currentShowId != null) {
    final found = await numberedOn(currentServer, currentShowId);
    if (found != null) return found;
  }
  final showIds = to.showIds.toSet();
  if (showIds.isNotEmpty && to.showTitle.isNotEmpty) {
    for (final cs in servers) {
      try {
        final show = (await clientFor(cs.server).search(to.showTitle))
            .firstWhereOrNull((item) => item.kind == MediaKind.show && sharesProviderId(item, showIds));
        if (show == null) continue;
        final found = await numberedOn(cs.server, show.id);
        if (found != null) return found;
      } catch (_) {}
    }
  }
  final ids = to.ids.toSet();
  if (ids.isNotEmpty && to.mediaTitle.isNotEmpty) {
    for (final cs in servers) {
      try {
        final match = (await clientFor(cs.server).search(to.mediaTitle)).firstWhereOrNull((item) => sharesProviderId(item, ids));
        if (match != null) return await detailOn(cs.server, match.id);
      } catch (_) {}
    }
  }
  return null;
}
