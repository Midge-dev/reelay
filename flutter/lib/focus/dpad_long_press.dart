import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, VoidCallback;

/// Detects a D-pad key held long enough to count as a long-press. A Timer
/// started on key-down and cancelled on key-up before it fires is what
/// actually detects the hold.
///
/// Originally built for the select/center button — GestureDetector.
/// onLongPress never fires for it on Android TV (it's pointer/touch-
/// gesture-only, and a held DPAD_CENTER/select key sends one raw key-down/
/// key-up pair with real elapsed time between them, no OS auto-repeat;
/// confirmed via `adb shell input keyevent --longpress KEYCODE_DPAD_CENTER`
/// during the flutter-reelay PoC — see project_flutter_focus_poc.md).
///
/// Also used for arrow-key holds (e.g. the nav rail's long-press-left-to-
/// home), standing in for DpadLongPress.kt's repeat-count-based approach:
/// that Kotlin implementation counts the OS's native key-repeat events,
/// which Flutter's cross-platform key event model doesn't expose
/// uniformly. The same held-timer technique works for any key, so one
/// detector class covers both cases rather than porting two different
/// mechanisms.
class DpadLongPressDetector {
  DpadLongPressDetector({
    required this.onLongPress,
    this.threshold = const Duration(milliseconds: 500),
    Set<LogicalKeyboardKey>? keys,
    this.consumeKeyDown = true,
  }) : keys = keys ?? selectKeys;

  final VoidCallback onLongPress;
  final Duration threshold;
  final Set<LogicalKeyboardKey> keys;

  // False for a key (e.g. an arrow key) whose short-press behavior is owned
  // by something else — Flutter's own default directional-focus traversal,
  // for the nav rail's long-press-left-to-home use. Consuming the KeyDown
  // there would block that default handling for every short left-press
  // app-wide, not just the long-press case. True (the original behavior)
  // for a key like select, where nothing else will invoke a short-press
  // action, so blocking default handling is exactly what should happen.
  final bool consumeKeyDown;

  // final, not const — a const Set literal of LogicalKeyboardKey values
  // doesn't compile (hit during the flutter-reelay PoC).
  static final selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.gameButtonA,
  };

  Timer? _timer;
  bool _fired = false;

  KeyEventResult handle(KeyEvent event) {
    if (!keys.contains(event.logicalKey)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _timer ??= Timer(threshold, () {
        _fired = true;
        onLongPress();
      });
      return consumeKeyDown ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      _timer?.cancel();
      _timer = null;
      if (_fired) {
        // Swallow the trailing release tied to the gesture that just fired
        // long-press, so it isn't also read as a click.
        _fired = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  void dispose() => _timer?.cancel();
}

/// The shared short-press/long-press split for a select/enter/gameButtonA
/// key: on KeyDown, hand it to [longPress] (so a hold is still tracked) and
/// swallow it, since nothing else should treat a bare select KeyDown as
/// anything on its own; on KeyUp, invoke [onClick] unless the hold already
/// fired as a long-press. [longPress] is nullable for a caller with no
/// long-press behavior at all, in which case every short press clicks.
///
/// Every widget that handles select itself (FocusableSurface,
/// WatchlistPoster, ContinueWatchingPoster) routes through this rather than
/// reimplementing it, so a fix here — or a future change to the gesture —
/// can't drift out of sync between them the way the click-on-select wiring
/// once did (WatchlistPoster/ContinueWatchingPoster forwarded straight to
/// DpadLongPressDetector.handle and never called onClick at all).
KeyEventResult handleDpadSelect(KeyEvent event, {required VoidCallback onClick, DpadLongPressDetector? longPress}) {
  if (!DpadLongPressDetector.selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
  if (event is KeyDownEvent) {
    longPress?.handle(event);
    return KeyEventResult.handled;
  }
  if (event is KeyUpEvent) {
    final swallowedByLongPress = longPress?.handle(event) == KeyEventResult.handled;
    if (!swallowedByLongPress) onClick();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
