import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/click_to_type_text_field.dart';
import 'package:reelay/screens/profiles/add_profile_dialog.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<void> Function({required String name, required String watchTogetherName, required String token})? onCreate,
  VoidCallback? onCancel,
  Widget Function(ValueChanged<String> onLinked)? linkPanelBuilder,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          AddProfileDialog(
            onCreate: onCreate ?? ({required name, required watchTogetherName, required token}) async {},
            onCancel: onCancel ?? () {},
            linkPanelBuilder: linkPanelBuilder,
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}

/// Drives the "Name" field's ClickToTypeTextField the same way a real
/// remote would: focus it, press Select to enter edit mode, then type.
Future<void> _typeName(WidgetTester tester, String value) async {
  final field = tester.widget<ClickToTypeTextField>(find.byType(ClickToTypeTextField).first);
  field.focusNode!.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pump();
  await tester.enterText(find.byType(EditableText), value);
  await tester.pump();
}

void main() {
  testWidgets('shows the kicker, title, and Plex sign-in row', (tester) async {
    await _pump(tester);

    expect(find.text('NEW PROFILE'), findsOneWidget);
    expect(find.text("Who's joining this device?"), findsOneWidget);
    expect(find.text('Plex'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget, reason: 'no name typed yet');
  });

  testWidgets('always shows a disabled Jellyfin row', (tester) async {
    await _pump(tester);

    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);
  });

  testWidgets('typing a name updates the accounts kicker', (tester) async {
    await _pump(tester);

    await _typeName(tester, 'Sam');

    expect(find.text("SAM'S ACCOUNTS"), findsOneWidget);
  });

  testWidgets('tapping Sign in shows the link panel and hides the Sign in button', (tester) async {
    await _pump(tester, linkPanelBuilder: (onLinked) => const Text('linking...'));

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('linking...'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('Create profile is a no-op until both a name and a linked account exist', (tester) async {
    var created = false;
    await _pump(
      tester,
      onCreate: ({required name, required watchTogetherName, required token}) async => created = true,
      linkPanelBuilder: (onLinked) => const SizedBox(),
    );

    await tester.tap(find.text('Create profile'));
    await tester.pump();
    expect(created, isFalse, reason: 'no name, no linked account yet');

    await _typeName(tester, 'Sam');
    await tester.tap(find.text('Create profile'));
    await tester.pump();
    expect(created, isFalse, reason: 'name typed but not signed in yet');
  });

  testWidgets('Create profile invokes onCreate with the typed name and linked token once both are ready', (tester) async {
    String? createdName;
    String? createdWatchTogetherName;
    String? createdToken;
    await _pump(
      tester,
      onCreate: ({required name, required watchTogetherName, required token}) async {
        createdName = name;
        createdWatchTogetherName = watchTogetherName;
        createdToken = token;
      },
      linkPanelBuilder: (onLinked) => _FakeLinkPanel(onLinked: onLinked),
    );

    await _typeName(tester, 'Sam');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.tap(find.text('link now'));
    await tester.pump();

    await tester.tap(find.text('Create profile'));
    await tester.pump();

    expect(createdName, 'Sam');
    expect(createdWatchTogetherName, 'Sam', reason: 'defaults to the name when left blank');
    expect(createdToken, 'fake-token');
  });

  testWidgets('Cancel invokes onCancel', (tester) async {
    var cancelled = false;
    await _pump(tester, onCancel: () => cancelled = true);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
  });
}

class _FakeLinkPanel extends StatelessWidget {
  final ValueChanged<String> onLinked;

  const _FakeLinkPanel({required this.onLinked});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onLinked('fake-token'),
      child: const Text('link now'),
    );
  }
}
