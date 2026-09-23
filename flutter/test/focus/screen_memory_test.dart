import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/focus/screen_memory.dart';

/// Three focusable items, the first autofocused unless the screen is being
/// returned to — the same shape every real screen follows.
class _Screen extends StatelessWidget {
  final List<String> ids;

  const _Screen({this.ids = const ['a', 'b', 'c']});

  @override
  Widget build(BuildContext context) {
    final restoring = ScreenMemory.restoringOf(context);
    return Column(
      children: [
        for (final (i, id) in ids.indexed)
          RememberFocus(
            key: ValueKey(id),
            id: id,
            child: Focus(
              debugLabel: id,
              autofocus: i == 0 && !restoring,
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
      ],
    );
  }
}

String? _focused() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _show(WidgetTester tester, ScreenMemory memory, {Widget screen = const _Screen()}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ScreenMemoryScope(key: ObjectKey(memory), memory: memory, child: screen),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _focus(WidgetTester tester, String id) async {
  final inside = tester.element(find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(SizedBox)));
  Focus.of(inside).requestFocus();
  await tester.pump();
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('coming back focuses the item that was focused on leaving', (tester) async {
    final memory = ScreenMemory();
    await _show(tester, memory);
    expect(_focused(), 'a');

    await _focus(tester, 'c');
    expect(_focused(), 'c');

    await _leave(tester);
    await _show(tester, memory);
    expect(_focused(), 'c');
  });

  testWidgets('a fresh visit starts on the default', (tester) async {
    final first = ScreenMemory();
    await _show(tester, first);
    await _focus(tester, 'c');

    await _leave(tester);
    await _show(tester, ScreenMemory());
    expect(_focused(), 'a');
  });

  testWidgets('a remembered item that is gone falls back to the first item', (tester) async {
    final memory = ScreenMemory()..focusedId = 'removed';
    await _show(tester, memory);
    expect(_focused(), 'a');
  });

  testWidgets('an item arriving after a key press does not take focus', (tester) async {
    final memory = ScreenMemory()..focusedId = 'late';
    await _show(tester, memory);
    expect(_focused(), 'a');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _show(tester, memory, screen: const _Screen(ids: ['a', 'b', 'late']));
    expect(_focused(), isNot('late'));
  });

  testWidgets('an item arriving with the page data takes focus back', (tester) async {
    final memory = ScreenMemory()..focusedId = 'late';
    await _show(tester, memory);
    expect(_focused(), 'a');

    await _show(tester, memory, screen: const _Screen(ids: ['a', 'b', 'late']));
    expect(_focused(), 'late');
  });

  test('carry moves a memory onto a rebuilt state', () {
    final before = Object();
    final after = Object();
    final memory = ScreenMemory.of(before);
    ScreenMemory.carry(before, after);
    expect(identical(ScreenMemory.of(after), memory), isTrue);
    expect(identical(ScreenMemory.of(Object()), memory), isFalse);
  });

  testWidgets('a focused item that goes away hands focus to the first item', (tester) async {
    final memory = ScreenMemory();
    await _show(tester, memory);
    await _focus(tester, 'c');
    expect(_focused(), 'c');

    // A refresh drops 'c' (it moved rows, or was removed).
    await _show(tester, memory, screen: const _Screen(ids: ['a', 'b']));
    await tester.pump();
    expect(_focused(), 'a');
  });
}
