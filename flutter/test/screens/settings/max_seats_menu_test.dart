import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/settings/max_seats_menu.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(size: Size(1920, 1080)), child: child),
    ),
  );
}

void main() {
  testWidgets('opens with the currently selected value focused and checked', (tester) async {
    await _pump(tester, MaxSeatsMenu(selected: 8, onSelect: (_) {}));
    await tester.pump();
    await tester.pump();

    expect(find.text('✓'), findsOneWidget);
  });

  testWidgets('selecting a row invokes onSelect with that value', (tester) async {
    int? selected;
    await _pump(tester, MaxSeatsMenu(selected: 8, onSelect: (v) => selected = v));
    await tester.pump();

    await tester.tap(find.text('4'));
    await tester.pump();

    expect(selected, 4);
  });

  testWidgets('pressing up at the first row and left/right do not throw or escape the menu', (tester) async {
    await _pump(tester, MaxSeatsMenu(selected: 2, onSelect: (_) {}));
    await tester.pump();
    await tester.pump();

    // Selected value (2) is the first option, so the menu opens with the
    // topmost row focused — pressing up here is exactly the boundary case
    // checklist item #8 is about. Since this widget tree has nothing
    // outside the menu to escape to, an unhandled key would surface here
    // as an exception rather than silently doing nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
