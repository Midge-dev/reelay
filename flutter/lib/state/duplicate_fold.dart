import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart' show ServerReachability;

/// One item paired with the server it came from — used only where content
/// is fanned out across more than one [PlexServer] and needs to be told
/// apart again (Home rows, library grids, search results, watchlist
/// resolution). Single-server call sites (episodes inside one show, a
/// movie's own detail fetch) never need this — see DESIGN.md's multi-server
/// hub non-negotiable (#10) for why folding, not per-item server fields
/// everywhere, is the shape this takes.
class Sourced<T> {
  final T value;
  final PlexServer server;
  final ServerReachability reachability;

  const Sourced(this.value, this.server, this.reachability);
}

/// A single work (movie/show), possibly present on more than one server.
/// [guid] is a representative scalar guid for the fold — the first copy
/// that had one, not necessarily what caused the fold (see [foldByGuid]:
/// two copies can fold together via a shared alternate id even when their
/// own scalar guids differ or are absent). Null means no copy in the fold
/// had a scalar guid at all. [copies] is never empty; [primary] is the
/// reachability-priority pick (local before relayed before unreachable).
/// Priority beyond reachability (direct play vs. transcode, quality) needs
/// per-file facts only a detail fetch has — DESIGN.md #10 defers that to
/// play time, not fold time, on purpose.
class FoldedWork<T> {
  final String? guid;
  final List<Sourced<T>> copies;

  const FoldedWork(this.guid, this.copies) : assert(copies.length > 0);

  Sourced<T> get primary => copies.first;
}

const _reachabilityRank = {
  ServerReachability.local: 0,
  ServerReachability.relayed: 1,
  ServerReachability.unreachable: 2,
};

/// Folds [items] into one [FoldedWork] per shared identity, preserving
/// overall input order (sort before calling if display order matters).
/// Two items fold together the moment they agree on *any* id — [guidOf]'s
/// scalar value, or any of [alternateIdsOf]'s (Plex's real `Guid` array:
/// imdb/tmdb/tvdb, present regardless of which agent is a given server's
/// *primary* one — see [PlexGuid]'s own doc comment for why a shared
/// scalar guid alone can miss a real duplicate). An item contributing no
/// id at all — [guidOf] returns null/empty and [alternateIdsOf] returns
/// nothing — never folds with anything else ("no id, no folding",
/// DESIGN.md #10), becoming its own singleton.
///
/// Implemented as union-find over item indices rather than a single-pass
/// group-by, since one item's alternate ids can transitively bridge two
/// other items that share no id directly (A-B share an imdb id, B-C share
/// a tmdb id — A and C must still land in the same fold).
List<FoldedWork<T>> foldByGuid<T>(
  List<Sourced<T>> items, {
  required String? Function(T value) guidOf,
  List<String> Function(T value)? alternateIdsOf,
}) {
  final ids = alternateIdsOf ?? (T _) => const <String>[];
  final n = items.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  final keyOwner = <String, int>{};
  for (var i = 0; i < n; i++) {
    final value = items[i].value;
    final guid = guidOf(value);
    final keys = [
      if (guid != null && guid.isNotEmpty) guid,
      ...ids(value).where((k) => k.isNotEmpty),
    ];
    for (final key in keys) {
      final owner = keyOwner[key];
      if (owner == null) {
        keyOwner[key] = i;
      } else {
        union(i, owner);
      }
    }
  }

  final groups = <int, List<int>>{};
  final order = <int>[];
  for (var i = 0; i < n; i++) {
    final root = find(i);
    if (!groups.containsKey(root)) order.add(root);
    groups.putIfAbsent(root, () => []).add(i);
  }

  return [
    for (final root in order)
      FoldedWork(
        groups[root]!
            .map((i) => guidOf(items[i].value))
            .firstWhere((g) => g != null && g.isNotEmpty, orElse: () => null),
        groups[root]!
            .map((i) => items[i])
            .toList()
          ..sort((a, b) => _reachabilityRank[a.reachability]!.compareTo(_reachabilityRank[b.reachability]!)),
      ),
  ];
}
