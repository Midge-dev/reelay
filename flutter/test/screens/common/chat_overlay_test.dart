import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/common/chat_overlay.dart';
import 'package:reelay/sync/relay_protocol.dart';

ChatMessage _msg(String username, String text) => ChatMessage(username: username, text: text, receivedAtMs: 0);

Future<void> _pump(WidgetTester tester, Stream<ChatMessage> messages, {ChatOverlayCorner corner = ChatOverlayCorner.bottomEnd}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ChatOverlay(messages: messages, corner: corner),
    ),
  );
  await tester.pump();
}

// A plain (non-broadcast) StreamController delivers via a microtask that
// resolves mid-pump, after that frame already built — the listener's
// setState needs one more pump to actually render.
Future<void> _add(WidgetTester tester, StreamController<ChatMessage> controller, ChatMessage message) async {
  controller.add(message);
  await tester.pump();
  await tester.pump();
}

// Every visible bubble schedules a 6s+300ms auto-expire Future.delayed;
// drain it before the test ends so no pending Timer outlives the tree.
Future<void> _drainBubbleTimers(WidgetTester tester) => tester.pump(const Duration(milliseconds: 6301));

void main() {
  testWidgets('a message appears as "username: text"', (tester) async {
    final controller = StreamController<ChatMessage>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream);

    await _add(tester, controller, _msg('Sean', 'hey'));

    expect(find.text('Sean: hey'), findsOneWidget);
    await _drainBubbleTimers(tester);
  });

  testWidgets('only the most recent 4 messages stay visible', (tester) async {
    final controller = StreamController<ChatMessage>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream);

    for (var i = 1; i <= 5; i++) {
      await _add(tester, controller, _msg('u', 'msg$i'));
    }

    expect(find.text('u: msg1'), findsNothing, reason: 'oldest message pushed out once over the cap');
    expect(find.text('u: msg2'), findsOneWidget);
    expect(find.text('u: msg5'), findsOneWidget);
    await _drainBubbleTimers(tester);
  });

  testWidgets('a message fades out and is removed after its visible window', (tester) async {
    final controller = StreamController<ChatMessage>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream);

    await _add(tester, controller, _msg('Sean', 'hey'));
    expect(find.text('Sean: hey'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 6000)); // MESSAGE_VISIBLE_MS elapses, starts fading
    await tester.pump(const Duration(milliseconds: 300)); // FADE_OUT_MS elapses, removed

    expect(find.text('Sean: hey'), findsNothing);
  });

  testWidgets('bottomEnd corner right-aligns text', (tester) async {
    final controller = StreamController<ChatMessage>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream, corner: ChatOverlayCorner.bottomEnd);

    await _add(tester, controller, _msg('Sean', 'hey'));

    final text = tester.widget<Text>(find.text('Sean: hey'));
    expect(text.textAlign, TextAlign.end);
    await _drainBubbleTimers(tester);
  });

  testWidgets('topStart corner left-aligns text', (tester) async {
    final controller = StreamController<ChatMessage>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream, corner: ChatOverlayCorner.topStart);

    await _add(tester, controller, _msg('Sean', 'hey'));

    final text = tester.widget<Text>(find.text('Sean: hey'));
    expect(text.textAlign, TextAlign.start);
    await _drainBubbleTimers(tester);
  });
}
