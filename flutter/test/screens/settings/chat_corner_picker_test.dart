import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/settings/chat_corner_picker.dart';

void main() {
  testWidgets('renders all four corner labels and marks the selected one', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatCornerPicker(selected: ChatOverlayCorner.bottomEnd, onSelect: (_) {}),
      ),
    );

    expect(find.text('Top left'), findsOneWidget);
    expect(find.text('Top right'), findsOneWidget);
    expect(find.text('Bottom left'), findsOneWidget);
    expect(find.text('Bottom right ✓'), findsOneWidget, reason: 'the selected corner gets a checkmark appended');
  });

  testWidgets('tapping a corner invokes onSelect with that corner', (tester) async {
    ChatOverlayCorner? selected;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatCornerPicker(selected: ChatOverlayCorner.bottomEnd, onSelect: (c) => selected = c),
      ),
    );

    await tester.tap(find.text('Top left'));
    await tester.pump();

    expect(selected, ChatOverlayCorner.topStart);
  });
}
