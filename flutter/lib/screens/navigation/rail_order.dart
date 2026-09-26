import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../../theme/phosphor_icons.dart';

/// The nav rail's movable items and the order they're shown in. Settings
/// and the avatar aren't here: they stay pinned to the foot of the rail.
///
/// An order is a list of ids — [railHome], [railSearch], [railWatchlist],
/// [railRooms] and one [railSectionId] per library — saved as
/// `AppSettings.railOrder`. An empty saved order means the default one.

const railHome = 'home';
const railSearch = 'search';
const railWatchlist = 'watchlist';
const railRooms = 'rooms';

String railSectionId(SectionGroup section) => 'section:${section.key}';

/// Home, Search, Watchlist, every library, then Watch Together.
List<String> defaultRailOrder(List<SectionGroup> sections) => [
  railHome,
  railSearch,
  railWatchlist,
  for (final s in sections) railSectionId(s),
  railRooms,
];

/// [saved] applied to the items that exist now: saved items keep their
/// saved order, a library that's gone is dropped, and one that's new since
/// slots in after whatever precedes it by default (the start, if nothing
/// does) — a new library lands among the others, not after Watch Together.
List<String> resolveRailOrder(List<String> saved, List<SectionGroup> sections) {
  final defaults = defaultRailOrder(sections);
  final order = <String>{
    for (final id in saved)
      if (defaults.contains(id)) id,
  }.toList();
  for (final (i, id) in defaults.indexed) {
    if (order.contains(id)) continue;
    final after = i == 0 ? -1 : order.indexOf(defaults[i - 1]);
    order.insert(after + 1, id);
  }
  return order;
}

/// [order] with [id] moved [delta] places (-1 up, +1 down), clamped to the
/// ends.
List<String> moveRailItem(List<String> order, String id, int delta) {
  final from = order.indexOf(id);
  if (from < 0) return order;
  final to = (from + delta).clamp(0, order.length - 1);
  if (to == from) return order;
  return [...order]
    ..removeAt(from)
    ..insert(to, id);
}

/// What an order is saved as: empty when it's the default, so libraries
/// added later keep taking their default places.
List<String> railOrderToSave(List<String> order, List<SectionGroup> sections) {
  return listEquals(order, defaultRailOrder(sections)) ? const [] : order;
}

/// How one rail item is drawn, wherever it's listed.
class RailItemLook {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const RailItemLook(this.label, this.icon, this.selectedIcon);
}

/// The label and icons for [id], or null for an id no item has.
RailItemLook? railItemLook(String id, List<SectionGroup> sections) {
  switch (id) {
    case railHome:
      return const RailItemLook(
        'Home',
        PhosphorIconsRegular.house,
        PhosphorIconsFill.house,
      );
    case railSearch:
      return const RailItemLook(
        'Search',
        PhosphorIconsRegular.magnifyingGlass,
        PhosphorIconsFill.magnifyingGlass,
      );
    case railWatchlist:
      return const RailItemLook(
        'Watchlist',
        PhosphorIconsRegular.bookmarkSimple,
        PhosphorIconsFill.bookmarkSimple,
      );
    case railRooms:
      return const RailItemLook(
        'Watch Together',
        PhosphorIconsRegular.usersThree,
        PhosphorIconsFill.usersThree,
      );
  }
  for (final s in sections) {
    if (railSectionId(s) != id) continue;
    final show = s.type == 'show';
    return RailItemLook(
      s.title,
      show
          ? PhosphorIconsRegular.televisionSimple
          : PhosphorIconsRegular.filmSlate,
      show ? PhosphorIconsFill.televisionSimple : PhosphorIconsFill.filmSlate,
    );
  }
  return null;
}
