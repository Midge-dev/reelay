import 'package:collection/collection.dart';

import '../data/media/media_models.dart';
import '../data/media/media_server.dart';
import '../data/media/media_server_client.dart';
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
/// [Person.globalId] (by exact name only when a server has none).
class PersonCredits {
  final List<ReachableServer> servers;
  final String clientIdentifier;
  final MediaServer origin;
  final Person person;

  PersonCredits({
    required this.servers,
    required this.clientIdentifier,
    required this.origin,
    required this.person,
  });

  String? _globalId;
  final _idOnServer = <String, String>{};

  MediaServerClient _api(MediaServer server) =>
      MediaServerClient.forServer(server, clientIdentifier);

  bool _sameName(String a) =>
      a.trim().toLowerCase() == person.name.trim().toLowerCase();

  /// Every title, folded across servers the same way as everywhere else.
  /// A server that fails to answer just contributes nothing.
  Future<List<FoldedWork<MediaItem>>> gather() async {
    _globalId = person.globalId;
    if (person.id != null) _idOnServer[origin.id] = person.id!;
    if (_globalId == null && person.id != null) {
      try {
        _globalId = (await _api(origin).searchPeople(person.name))
            .firstWhereOrNull((p) => p.id == person.id)
            ?.globalId;
      } catch (_) {}
    }

    final perServer = await Future.wait(
      servers.map((s) async {
        try {
          final id = await _resolveId(s.server);
          if (id == null) return const <Sourced<MediaItem>>[];
          final items = await _api(s.server).fetchPersonMedia(id);
          return [for (final i in items) Sourced(i, s.server, s.reachability)];
        } catch (_) {
          return const <Sourced<MediaItem>>[];
        }
      }),
    );
    final works = foldWorks(perServer.expand((l) => l).toList());
    // Newest first; undated titles last, then by name.
    works.sort((a, b) {
      final ya = a.primary.value.year ?? 0;
      final yb = b.primary.value.year ?? 0;
      if (ya != yb) return yb.compareTo(ya);
      return a.primary.value.title.compareTo(b.primary.value.title);
    });
    return works;
  }

  Future<String?> _resolveId(MediaServer server) async {
    final known = _idOnServer[server.id];
    if (known != null) return known;
    final found = await _api(server).searchPeople(person.name);
    final match = _globalId != null
        ? found.firstWhereOrNull((p) => p.globalId == _globalId)
        : found.firstWhereOrNull((p) => _sameName(p.name));
    if (match?.id != null) _idOnServer[server.id] = match!.id!;
    return match?.id;
  }

  /// What the person did on [work], from its primary copy's full detail
  /// (the list response doesn't carry characters or jobs).
  Future<PersonCredit?> creditOn(FoldedWork<MediaItem> work) async {
    final copy = work.primary;
    final detail = await _api(copy.server).fetchDetail(copy.value.id);
    final idHere = _idOnServer[copy.server.id];
    bool isThem(Person p) {
      if (_globalId != null && p.globalId != null)
        return p.globalId == _globalId;
      if (idHere != null && p.id != null) return p.id == idHere;
      return _sameName(p.name);
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
