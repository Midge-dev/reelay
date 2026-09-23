import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps Right inside a horizontal row. At a row's last item, directional
/// traversal otherwise finds the nearest thing to the right anywhere on the
/// page — pressing Right past the last cast member dropped focus into the
/// row below. At the end of a row the press now simply stops. Left is left
/// alone: at a row's start it is how the nav rail is reached.
class RowEndStop extends StatelessWidget {
  final Widget child;

  const RowEndStop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.ignored;
        }
        final focused = FocusManager.instance.primaryFocus;
        if (focused == null || focused == node) return KeyEventResult.ignored;
        final from = focused.rect;
        final hasNext = node.traversalDescendants.any((n) {
          if (n == focused || !n.canRequestFocus) return false;
          final r = n.rect;
          final sameLine = r.top < from.bottom && r.bottom > from.top;
          return sameLine && r.center.dx > from.center.dx;
        });
        return hasNext ? KeyEventResult.ignored : KeyEventResult.handled;
      },
      child: child,
    );
  }
}
