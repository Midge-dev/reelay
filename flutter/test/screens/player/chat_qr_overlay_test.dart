import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/player/chat_qr_overlay.dart';

void main() {
  testWidgets('shows the "Join the chat" heading', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatQrOverlay(chatUrl: 'https://relay.example.com/chat?room=1', onDismiss: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('Join the chat'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30001));
  });

  testWidgets('auto-dismisses after 30 seconds', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatQrOverlay(chatUrl: 'https://relay.example.com/chat?room=1', onDismiss: () => dismissed = true),
      ),
    );
    await tester.pump();

    expect(dismissed, isFalse);
    await tester.pump(const Duration(milliseconds: 30001));

    expect(dismissed, isTrue);
  });

  testWidgets('does not fire before 30 seconds', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChatQrOverlay(chatUrl: 'https://relay.example.com/chat?room=1', onDismiss: () => dismissed = true),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 29000));
    expect(dismissed, isFalse);

    await tester.pump(const Duration(milliseconds: 1001));
    expect(dismissed, isTrue);
  });
}
