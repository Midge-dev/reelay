import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/library/search_keyboard.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(size: Size(1920, 1080)), child: child),
    ),
  );
}

void main() {
  testWidgets('tapping a letter key invokes onChar with that letter', (tester) async {
    String? typed;
    await _pump(
      tester,
      SearchKeyboard(onChar: (c) => typed = c, onBackspace: () {}, onClear: () {}),
    );

    await tester.tap(find.text('A'));
    await tester.pump();

    expect(typed, 'A');
  });

  testWidgets('tapping DELETE invokes onBackspace, not onClear', (tester) async {
    var backspaces = 0;
    var clears = 0;
    await _pump(
      tester,
      SearchKeyboard(onChar: (_) {}, onBackspace: () => backspaces++, onClear: () => clears++),
    );

    await tester.tap(find.text('⌫ DELETE'));
    await tester.pump();

    expect(backspaces, 1);
    expect(clears, 0);
  });

  testWidgets('holding DELETE invokes onClear via the long-press detector', (tester) async {
    var clears = 0;
    await _pump(
      tester,
      SearchKeyboard(onChar: (_) {}, onBackspace: () {}, onClear: () => clears++),
    );

    final deleteFinder = find.ancestor(of: find.text('⌫ DELETE'), matching: find.byType(Focus)).first;
    final focusNode = tester.widget<Focus>(deleteFinder).focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(clears, 1);
  });

  testWidgets('arrow-right moves focus from A to B', (tester) async {
    await _pump(
      tester,
      SearchKeyboard(onChar: (_) {}, onBackspace: () {}, onClear: () {}),
    );

    final aFocus = tester.widget<Focus>(find.ancestor(of: find.text('A'), matching: find.byType(Focus)).first).focusNode!;
    final bFocus = tester.widget<Focus>(find.ancestor(of: find.text('B'), matching: find.byType(Focus)).first).focusNode!;

    aFocus.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(aFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();

    expect(bFocus.hasFocus, isTrue);
  });

  testWidgets('arrow-up on the top row does not throw (trapped, not escaping)', (tester) async {
    await _pump(
      tester,
      SearchKeyboard(onChar: (_) {}, onBackspace: () {}, onClear: () {}),
    );

    final aFocus = tester.widget<Focus>(find.ancestor(of: find.text('A'), matching: find.byType(Focus)).first).focusNode!;
    aFocus.requestFocus();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(aFocus.hasFocus, isTrue, reason: 'trapped at the boundary, focus should stay put');
  });
}
