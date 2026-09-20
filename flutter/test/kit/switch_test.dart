import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/switch.dart';

void main() {
  testWidgets('tapping the switch toggles checked state via the callback', (tester) async {
    var checked = false;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) => AppSwitch(
            checked: checked,
            onCheckedChange: (value) => setState(() => checked = value),
          ),
        ),
      ),
    );

    expect(checked, isFalse);

    await tester.tap(find.byType(AppSwitch));
    await tester.pump();

    expect(checked, isTrue);
  });
}
