import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/focus/smooth_traversal.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  testWidgets(
    'moving down to an off-screen row eases the page there instead of jumping',
    (tester) async {
      final controller = ScrollController();
      final rows = List.generate(8, (i) => FocusNode(debugLabel: 'row $i'));
      addTearDown(() {
        controller.dispose();
        for (final n in rows) {
          n.dispose();
        }
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            // WidgetsApp's own arrow-key → directional-focus wiring.
            child: Shortcuts(
              shortcuts: WidgetsApp.defaultShortcuts,
              child: Actions(
                actions: WidgetsApp.defaultActions,
                child: FocusTraversalGroup(
                  policy: smoothFocusTraversalPolicy(),
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      children: [
                        for (final node in rows)
                          Focus(
                            focusNode: node,
                            child: const SizedBox(width: 800, height: 400),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      rows[0].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(rows[1].hasFocus, isTrue, reason: 'focus moves at once');

      await tester.pump(AppMotion.pageScroll ~/ 3);
      final midway = controller.offset;
      expect(midway, greaterThan(0));
      expect(
        midway,
        lessThan(200),
        reason: 'still on its way, not cut to the end',
      );

      await tester.pump(AppMotion.pageScroll);
      expect(
        controller.offset,
        200,
        reason: 'settles with the row just in view',
      );
    },
  );
}
