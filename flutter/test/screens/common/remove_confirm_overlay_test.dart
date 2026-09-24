import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/remove_confirm_overlay.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onConfirm,
  required VoidCallback onCancel,
  bool compact = false,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          RemoveConfirmOverlay(message: 'Remove this item?', onConfirm: onConfirm, onCancel: onCancel, compact: compact),
        ],
      ),
    ),
  );
  // Let the postFrameCallback requestFocus() land.
  await tester.pump();
}

void main() {
  testWidgets('shows the message and Remove/Cancel buttons', (tester) async {
    await _pump(tester, onConfirm: () {}, onCancel: () {});

    expect(find.text('Remove this item?'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('tapping Remove confirms', (tester) async {
    var confirmed = false;
    await _pump(tester, onConfirm: () => confirmed = true, onCancel: () {});

    await tester.tap(find.text('Remove'));
    await tester.pump();

    expect(confirmed, isTrue);
  });

  testWidgets('tapping Cancel cancels', (tester) async {
    var cancelled = false;
    await _pump(tester, onConfirm: () {}, onCancel: () => cancelled = true);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('losing focus after having been focused invokes onCancel', (tester) async {
    var cancelled = false;
    final elsewhereFocus = FocusNode(debugLabel: 'elsewhere');
    addTearDown(elsewhereFocus.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Focus(focusNode: elsewhereFocus, child: const SizedBox(width: 10, height: 10)),
            RemoveConfirmOverlay(message: 'Remove this item?', onConfirm: () {}, onCancel: () => cancelled = true),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(cancelled, isFalse, reason: 'the initial requestFocus() landing must not itself read as a loss');

    elsewhereFocus.requestFocus();
    await tester.pump();

    expect(cancelled, isTrue);
  });
}
