import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Development builds only (debug and profile; compiled out of release):
/// writes every key event and every focus move to the log, so a focus bug
/// seen on the TV can be read back afterwards:
///
///     adb logcat -s flutter | grep '\[focus\]'
///
/// Each focus line names the node (its debugLabel, else its widget) and
/// whether it's on screen.
void startFocusLog() {
  if (kReleaseMode) return;
  var last = '';
  FocusManager.instance.addListener(() {
    final node = FocusManager.instance.primaryFocus;
    final label = node == null ? 'NOTHING' : describeFocusNode(node);
    if (label == last) return;
    last = label;
    debugPrint('[focus] -> $label');
  });
  HardwareKeyboard.instance.addHandler((event) {
    final kind = switch (event) {
      KeyDownEvent() => 'down',
      KeyRepeatEvent() => 'repeat',
      KeyUpEvent() => 'up',
      _ => event.runtimeType.toString(),
    };
    debugPrint('[focus] key ${event.logicalKey.keyLabel} $kind');
    return false;
  });
}

String describeFocusNode(FocusNode node) {
  final label = node.debugLabel ?? node.context?.widget.runtimeType.toString() ?? node.runtimeType.toString();
  final rect = node.context != null && node.context!.mounted ? node.rect : null;
  final where = rect == null ? 'no rect' : '${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()}';
  return '$label [$where${node.canRequestFocus ? '' : ', unfocusable'}${node.skipTraversal ? ', skips traversal' : ''}]';
}

/// One line about something a screen did that affects focus.
void focusLogNote(String text) {
  if (!kReleaseMode) debugPrint('[focus] $text');
}
