import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/theme/tokens.dart';

/// relay/chat.html carries its own copy of every theme's palette (the phone
/// page follows the theme of the TV that showed the QR). A theme changed in
/// tokens.dart must be changed there too — this fails until it is.
void main() {
  // The phone's own bubbles are filled with --a900, and these four TV values
  // are either too light for ink on top (Projection) or indistinguishable
  // from the page ground on a phone; design_handoff_reelay_chat sets its own.
  const chatOnlyAccent900 = {
    ThemeId.projection: 0xFF2A2C36,
    ThemeId.harbour: 0xFF1B2127,
    ThemeId.sage: 0xFF19211D,
    ThemeId.clay: 0xFF241C18,
  };

  final html = File('../relay/chat.html').readAsStringSync();

  Map<String, int> cssFor(ThemeId id) {
    final block = RegExp('\\[data-theme="${id.name}"\\]\\s*\\{([^}]*)\\}').firstMatch(html);
    expect(block, isNotNull, reason: 'chat.html has no [data-theme="${id.name}"] block');
    return {
      for (final m in RegExp(r'--([\w-]+):#([0-9A-Fa-f]{6})').allMatches(block!.group(1)!))
        m.group(1)!: 0xFF000000 | int.parse(m.group(2)!, radix: 16),
    };
  }

  for (final id in ThemeId.values) {
    test('${id.name} matches tokens.dart', () {
      final p = nocturnePalette(id);
      final css = cssFor(id);
      final expected = <String, Color>{
        'canvas': p.canvas,
        'bg': p.background,
        'surface': p.surface,
        'raised': p.surfaceRaised,
        'overlay': p.surfaceOverlay,
        'line': p.line,
        'line-strong': p.lineStrong,
        'ink': p.ink,
        'ink2': p.ink2,
        'ink3': p.ink3,
        'ink4': p.ink4,
        'accent': p.accent,
        'a300': p.accent300,
        'a700': p.accent700,
        'a900': Color(chatOnlyAccent900[id] ?? p.accent900.toARGB32()),
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(css[key], value.toARGB32(), reason: '--$key in chat.html (${id.name})');
      }
    });
  }
}
