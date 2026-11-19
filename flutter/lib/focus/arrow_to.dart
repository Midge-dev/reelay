import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Sends one arrow out of [child] to [target], when directional traversal
/// would pick the wrong neighbour. Traversal prefers whatever overlaps the
/// focused item sideways, so a control set far to one side gets skipped:
/// Home's Watch Together bar keeps its buttons at the right, and Down from
/// the hero's Resume (at the left) jumped straight past it into the row
/// underneath. With no [target] on screen the press goes on as usual.
class ArrowTo extends StatelessWidget {
  final LogicalKeyboardKey direction;
  final FocusNode? target;
  final Widget child;

  const ArrowTo({
    super.key,
    required this.direction,
    required this.target,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent || event.logicalKey != direction) {
          return KeyEventResult.ignored;
        }
        final to = target;
        if (to == null ||
            to.context == null ||
            !to.canRequestFocus ||
            to.hasFocus) {
          return KeyEventResult.ignored;
        }
        to.requestFocus();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// Up and Down out of [child] go to the nearest row of focusable items in
/// that direction, and within it to the item closest sideways — where
/// plain traversal would favour anything that overlaps sideways, however
/// far down. For a bar whose buttons sit at one side (Home's Watch
/// Together bar), so neither key jumps past the row next to it.
class NearestRowTraversal extends StatelessWidget {
  final Widget child;

  const NearestRowTraversal({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
        if (!down && event.logicalKey != LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.ignored;
        }
        final focused = FocusManager.instance.primaryFocus;
        final scope = focused?.nearestScope;
        if (focused == null || scope == null) return KeyEventResult.ignored;
        final from = focused.rect;
        final inside = node.traversalDescendants.toSet();
        final candidates = [
          for (final n in scope.traversalDescendants)
            if (!inside.contains(n) && n.canRequestFocus && !n.rect.isEmpty)
              if (down
                  ? n.rect.top >= from.bottom - 1
                  : n.rect.bottom <= from.top + 1)
                n,
        ];
        if (candidates.isEmpty) return KeyEventResult.ignored;
        double gap(FocusNode n) =>
            down ? n.rect.top - from.bottom : from.top - n.rect.bottom;
        final nearest = candidates.map(gap).reduce((a, b) => a < b ? a : b);
        final row = candidates.where((n) => gap(n) <= nearest + 24);
        double sideways(FocusNode n) =>
            (n.rect.center.dx - from.center.dx).abs();
        row.reduce((a, b) => sideways(a) <= sideways(b) ? a : b).requestFocus();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
