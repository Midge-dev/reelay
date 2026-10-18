/// Interleaves several servers' Continue Watching lists into one, most
/// recently played first.
///
/// Each server already orders its own list, so that order is kept exactly;
/// only how the lists interleave is decided by [playedAt]. A title with no
/// time (a show's next episode, never played) stands where its server put
/// it, taking the time of the nearest title above it, or below it at the top.
/// A list with no times at all goes after every list that has them; ties
/// go to the earlier list.
List<T> mergeByRecency<T>(List<List<T>> lists, int? Function(T) playedAt) {
  final keys = [for (final list in lists) _filledTimes(list, playedAt)];
  final heads = List.filled(lists.length, 0);
  final merged = <T>[];
  while (true) {
    int? pick;
    for (var l = 0; l < lists.length; l++) {
      if (heads[l] >= lists[l].length) continue;
      if (pick == null || keys[l][heads[l]] > keys[pick][heads[pick]]) pick = l;
    }
    if (pick == null) return merged;
    merged.add(lists[pick][heads[pick]++]);
  }
}

List<int> _filledTimes<T>(List<T> list, int? Function(T) playedAt) {
  final times = [for (final item in list) playedAt(item)];
  int? carry;
  for (var i = 0; i < times.length; i++) {
    carry = times[i] ??= carry;
  }
  carry = null;
  for (var i = times.length - 1; i >= 0; i--) {
    carry = times[i] ??= carry;
  }
  return [for (final t in times) t ?? -1];
}
