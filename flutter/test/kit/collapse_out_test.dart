import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/collapse_out.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  // Screen 21, "Gone on release: the card collapses its width over 180 ms
  // and the grid closes up."
  group('LeavingItems', () {
    test('a removed item stays where it was, leaving, then goes', () {
      var expired = 0;
      final leaving = LeavingItems<String>(idOf: (s) => s, onExpired: () => expired++);
      expect(leaving.merge(['a', 'b', 'c', 'd']).map((e) => e.item), ['a', 'b', 'c', 'd']);

      final merged = leaving.merge(['a', 'c', 'd']);
      expect(merged.map((e) => e.item), ['a', 'b', 'c', 'd'], reason: 'b collapses where it was');
      expect(merged.map((e) => e.leaving), [false, true, false, false]);
      expect(merged.where((e) => !e.leaving).map((e) => e.index), [0, 1, 2], reason: "the others keep their real indexes");
      leaving.dispose();
    });

    testWidgets('after the collapse it is gone, and the owner is told to rebuild', (tester) async {
      var expired = 0;
      final leaving = LeavingItems<String>(idOf: (s) => s, onExpired: () => expired++);
      leaving.merge(['a', 'b']);
      leaving.merge(['a']);
      await tester.pump(AppMotion.collapse);
      expect(expired, 1);
      expect(leaving.merge(['a']).map((e) => e.item), ['a']);
      leaving.dispose();
    });

    test('an item that comes back (Undo) is simply there again', () {
      final leaving = LeavingItems<String>(idOf: (s) => s, onExpired: () {});
      leaving.merge(['a', 'b']);
      leaving.merge(['a']);
      final back = leaving.merge(['a', 'b']);
      expect(back.map((e) => (e.item, e.leaving)), [('a', false), ('b', false)]);
      leaving.dispose();
    });

    test('nothing leaves on the first look', () {
      final leaving = LeavingItems<String>(idOf: (s) => s, onExpired: () {});
      expect(leaving.merge(['a']).single.leaving, isFalse);
      leaving.dispose();
    });
  });

  group('CollapseOut', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(const Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              CollapseOut(child: SizedBox(width: 200, height: 100)),
              SizedBox(width: 50, height: 100, key: ValueKey('next')),
            ],
          ),
        ));

    testWidgets('narrows to nothing over the collapse, and the next card closes up', (tester) async {
      await pump(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('next'))).dx, 200);
      await tester.pump(AppMotion.collapse ~/ 2);
      expect(tester.getTopLeft(find.byKey(const ValueKey('next'))).dx, closeTo(100, 2));
      await tester.pump(AppMotion.collapse ~/ 2);
      expect(tester.getTopLeft(find.byKey(const ValueKey('next'))).dx, 0);
    });

    testWidgets('is never focusable', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CollapseOut(child: Focus(focusNode: node, child: const SizedBox(width: 10, height: 10))),
      ));
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });
}
