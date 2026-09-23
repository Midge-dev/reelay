import 'package:flutter/widgets.dart';

/// Ports Compose's `BackHandler(onBack)` — intercepts the system back
/// button/gesture (Android TV remote's back/menu key) via PopScope, since
/// this app has no real Navigator route stack to pop (AppRoot switches on
/// AppState directly, same as MainActivity.kt's approach).
///
/// Exactly one handler answers each Back press. PopScope alone notifies
/// *every* mounted scope, so a panel over a screen (the rooms panel, the
/// server switcher, the undo chip) used to close itself *and* navigate the
/// screen underneath back a level. The one that answers is the innermost
/// enabled handler around the focused widget — the panel you are in, not
/// the page behind it — or, when none contains focus, the most recently
/// mounted enabled one (Compose's "last registered wins").
class BackHandler extends StatefulWidget {
  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  const BackHandler({super.key, this.enabled = true, required this.onBack, required this.child});

  @override
  State<BackHandler> createState() => _BackHandlerState();
}

class _BackHandlerState extends State<BackHandler> {
  static final List<_BackHandlerState> _mounted = [];

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    super.dispose();
  }

  /// Depth of this handler's element if it is an ancestor of [focus], else
  /// null.
  int? _depthAbove(BuildContext focus) {
    final self = context as Element;
    var found = false;
    var depth = 0;
    focus.visitAncestorElements((ancestor) {
      if (ancestor == self) {
        found = true;
        return false;
      }
      return true;
    });
    if (!found) return null;
    self.visitAncestorElements((_) {
      depth++;
      return true;
    });
    return depth;
  }

  static _BackHandlerState? _winner() {
    final candidates = _mounted.where((h) => h.mounted && h.widget.enabled).toList();
    if (candidates.isEmpty) return null;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null) {
      _BackHandlerState? best;
      var bestDepth = -1;
      for (final h in candidates) {
        final d = h._depthAbove(focus);
        if (d != null && d > bestDepth) {
          best = h;
          bestDepth = d;
        }
      }
      if (best != null) return best;
    }
    return candidates.last;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !widget.enabled) return;
        if (identical(_winner(), this)) widget.onBack();
      },
      child: widget.child,
    );
  }
}
