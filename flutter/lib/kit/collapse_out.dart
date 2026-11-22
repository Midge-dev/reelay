import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// One place in a row or grid: an item still on it ([index] its real
/// position, for whatever the builder keys on it), or one just taken off,
/// [leaving] — drawn in a [CollapseOut] where it was.
class Slot<T> {
  final T item;
  final bool leaving;
  final int index;
  const Slot._(this.item, this.leaving, this.index);
}

/// Screen 21, "Gone on release": a card taken off a list collapses where it
/// was over [AppMotion.collapse], and the row closes up. A row or grid's
/// owner [merge]s each new list through this to get its slots: the items
/// still on it, plus any that just left, at their old places, for the
/// length of the collapse — then [onExpired] says to rebuild without them.
///
/// The list itself (and so focus, Undo and the rest) changes at once; only
/// the drawing lags. An item that comes back mid-collapse (Undo) is simply
/// there again.
class LeavingItems<T> {
  LeavingItems({required this.idOf, required this.onExpired});

  final String Function(T item) idOf;
  final VoidCallback onExpired;

  List<T>? _last;
  final _leaving = <String, ({T item, int at})>{};
  final _timers = <String, Timer>{};

  List<Slot<T>> merge(List<T> current) {
    final ids = {for (final item in current) idOf(item)};
    for (final id in _leaving.keys.where(ids.contains).toList()) {
      _leaving.remove(id);
      _timers.remove(id)?.cancel();
    }
    final last = _last;
    if (last != null) {
      for (var i = 0; i < last.length; i++) {
        final id = idOf(last[i]);
        if (ids.contains(id) || _leaving.containsKey(id)) continue;
        _leaving[id] = (item: last[i], at: i);
        _timers[id] = Timer(AppMotion.collapse, () {
          _leaving.remove(id);
          _timers.remove(id);
          onExpired();
        });
      }
    }
    _last = current;
    final slots = [for (var i = 0; i < current.length; i++) Slot._(current[i], false, i)];
    final gone = _leaving.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    for (final g in gone) {
      slots.insert(g.at.clamp(0, slots.length), Slot._(g.item, true, -1));
    }
    return slots;
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// A card on its way out: its width collapses to nothing over
/// [AppMotion.collapse], linear — AppMotion.exit's curve, since it's
/// leaving — so what follows it closes up. Never focusable or tappable.
class CollapseOut extends StatefulWidget {
  final Widget child;

  const CollapseOut({super.key, required this.child});

  @override
  State<CollapseOut> createState() => _CollapseOutState();
}

class _CollapseOutState extends State<CollapseOut> with SingleTickerProviderStateMixin {
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: AppMotion.collapse,
    value: 1,
  )..reverse();

  @override
  void dispose() {
    _collapse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: IgnorePointer(
        child: SizeTransition(
          axis: Axis.horizontal,
          alignment: AlignmentDirectional.centerStart,
          sizeFactor: _collapse,
          child: widget.child,
        ),
      ),
    );
  }
}
