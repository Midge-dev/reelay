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
/// [guid] is Plex's cross-server agent guid — null means the source item
/// had none, so it never folds with anything else ("no id, no folding",
/// DESIGN.md #10). [copies] is never empty; [primary] is the
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

/// Folds [items] into one [FoldedWork] per shared guid, preserving overall
/// input order (sort before calling if display order matters). Items with
/// no guid each become their own singleton fold, never merged with
/// anything else.
List<FoldedWork<T>> foldByGuid<T>(
  List<Sourced<T>> items, {
  required String? Function(T value) guidOf,
}) {
  final byKey = <String, List<Sourced<T>>>{};
  final order = <String>[];
  var unfoldedCount = 0;
  for (final item in items) {
    final guid = guidOf(item.value);
    final key = (guid == null || guid.isEmpty) ? '#unfolded-${unfoldedCount++}' : guid;
    final bucket = byKey[key];
    if (bucket == null) {
      byKey[key] = [item];
      order.add(key);
    } else {
      bucket.add(item);
    }
  }
  return [
    for (final key in order)
      FoldedWork(
        key.startsWith('#unfolded-') ? null : key,
        [...byKey[key]!]..sort((a, b) => _reachabilityRank[a.reachability]!.compareTo(_reachabilityRank[b.reachability]!)),
      ),
  ];
}
