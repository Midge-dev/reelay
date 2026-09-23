import 'package:collection/collection.dart';

import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart' show ReachableServer;
import '../data/plex/plex_server_api.dart';
import 'duplicate_fold.dart';

/// What one person did on one title (screen 03c): the caption names the
/// character, else the job, and the chips split on [acted]/[directed].
class PersonCredit {
  final String? character;
  final bool acted;
  final bool directed;
  final bool wrote;

  const PersonCredit({
    this.character,
    this.acted = false,
    this.directed = false,
    this.wrote = false,
  });

  String? get label {
    final c = character?.trim();
    if (c != null && c.isNotEmpty) return c;
    if (directed) return 'Director';
    if (wrote) return 'Writer';
    return null;
  }
}

/// Screen 03c — everything a person is in, across every connected server.
/// A person's tag id only means something on the server it came from, so
/// each other server is asked for the same person by name and matched on
/// Plex's global `tagKey` (by exact name only when a server has none).
class PersonCredits {
  final List<ReachableServer> servers;
  final String clientIdentifier;
  final PlexServer origin;
  final PlexPerson person;

  PersonCredits({
    required this.servers,
    required this.clientIdentifier,
    required this.origin,
    required this.person,
  });

  String? _tagKey;
  final _idOnServer = <String, int>{};

  PlexServerApi _api(PlexServer server) =>
      PlexServerApi(server, clientIdentifier);

  bool _sameName(String a) =>
      a.trim().toLowerCase() == person.tag.trim().toLowerCase();

  /// Every title, folded across servers the same way as everywhere else.
  /// A server that fails to answer just contributes nothing.
  Future<List<FoldedWork<PlexLibraryItem>>> gather() async {
    _tagKey = person.tagKey;
    if (person.id != null) _idOnServer[origin.machineIdentifier] = person.id!;
    if (_tagKey == null && person.id != null) {
      try {
        _tagKey = (await _api(origin).searchPeople(person.tag))
            .firstWhereOrNull((p) => p.id == person.id)
            ?.tagKey;
      } catch (_) {}
    }

    final perServer = await Future.wait(
      servers.map((s) async {
        try {
          final id = await _resolveId(s.server);
          if (id == null) return const <Sourced<PlexLibraryItem>>[];
          final items = await _api(s.server).fetchPersonMedia(id);
          return [for (final i in items) Sourced(i, s.server, s.reachability)];
        } catch (_) {
          return const <Sourced<PlexLibraryItem>>[];
        }
      }),
    );
    final works = foldByGuid(
      perServer.expand((l) => l).toList(),
      guidOf: (i) => i.guid,
      alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
    );
    // Newest first; undated titles last, then by name.
    works.sort((a, b) {
      final ya = a.primary.value.year ?? 0;
      final yb = b.primary.value.year ?? 0;
      if (ya != yb) return yb.compareTo(ya);
      return a.primary.value.title.compareTo(b.primary.value.title);
    });
    return works;
  }

  Future<int?> _resolveId(PlexServer server) async {
    final known = _idOnServer[server.machineIdentifier];
    if (known != null) return known;
    final found = await _api(server).searchPeople(person.tag);
    final match = _tagKey != null
        ? found.firstWhereOrNull((p) => p.tagKey == _tagKey)
        : found.firstWhereOrNull((p) => _sameName(p.tag));
    if (match?.id != null) _idOnServer[server.machineIdentifier] = match!.id!;
    return match?.id;
  }

  /// What the person did on [work], from its primary copy's full detail
  /// (the list response doesn't carry characters or jobs).
  Future<PersonCredit?> creditOn(FoldedWork<PlexLibraryItem> work) async {
    final copy = work.primary;
    final detail = await _api(copy.server)
        .fetchMovieDetail(copy.value.ratingKey);
    final idHere = _idOnServer[copy.server.machineIdentifier];
    bool isThem(PlexPerson p) {
      if (_tagKey != null && p.tagKey != null) return p.tagKey == _tagKey;
      if (idHere != null && p.id != null) return p.id == idHere;
      return _sameName(p.tag);
    }

    final role = detail.roles.firstWhereOrNull(isThem);
    return PersonCredit(
      character: role?.role,
      acted: role != null,
      directed: detail.directors.any(isThem),
      wrote: detail.writers.any(isThem),
    );
  }
}
