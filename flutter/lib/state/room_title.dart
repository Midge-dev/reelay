import 'package:collection/collection.dart';

import '../data/media/media_models.dart';
import '../data/media/media_server.dart';
import '../data/media/media_server_client.dart';
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
