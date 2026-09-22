import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/screens/common/click_to_type_text_field.dart';
import 'package:reelay/screens/profiles/profile_picker_screen.dart';

const _profiles = [
  Profile(id: 'p1', name: 'Sam', watchTogetherName: 'Sammy', plexUsername: 'GrimLad'),
  Profile(id: 'p2', name: 'Maya', watchTogetherName: 'Maya', plexUsername: 'mayawrenn'),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Profile> profiles = _profiles,
  ValueChanged<Profile>? onSelectProfile,
  Future<void> Function({required String name, required String watchTogetherName, required String token})? onAddProfile,
  Widget Function(ValueChanged<String> onLinked)? linkPanelBuilder,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ProfilePickerScreen(
        profiles: profiles,
        onSelectProfile: onSelectProfile ?? (_) {},
        onAddProfile: onAddProfile ?? ({required name, required watchTogetherName, required token}) async {},
        linkPanelBuilder: linkPanelBuilder,
      ),
    ),
  );
  await tester.pump();
}

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
  testWidgets("shows Who's watching and every profile's name and Plex username", (tester) async {
    await _pump(tester);

    expect(find.text("Who's watching?"), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Plex · GrimLad'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Plex · mayawrenn'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('tapping a profile invokes onSelectProfile with that profile', (tester) async {
    Profile? selected;
    await _pump(tester, onSelectProfile: (p) => selected = p);

    await tester.tap(find.byType(AppCard).at(0));
    await tester.pump();

    expect(selected?.id, 'p1');
  });

  testWidgets('tapping Add opens the add-profile dialog', (tester) async {
    await _pump(tester);

    expect(find.text('NEW PROFILE'), findsNothing);

    await tester.tap(find.byType(AppCard).last);
    await tester.pump();

    expect(find.text('NEW PROFILE'), findsOneWidget);
  });

  testWidgets('completing add-profile invokes onAddProfile with the typed name and linked token', (tester) async {
    String? addedName;
    String? addedToken;
    await _pump(
      tester,
      onAddProfile: ({required name, required watchTogetherName, required token}) async {
        addedName = name;
        addedToken = token;
      },
      linkPanelBuilder: (onLinked) => _FakeLinkPanel(onLinked: onLinked),
    );

    await tester.tap(find.byType(AppCard).last);
    await tester.pump();

    await _typeName(tester, 'Kids');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.tap(find.text('link now'));
    await tester.pump();
    await tester.tap(find.text('Create profile'));
    await tester.pump();

    expect(addedName, 'Kids');
    expect(addedToken, 'fake-token');
  });

  testWidgets('cancelling the add-profile dialog closes it without calling onAddProfile', (tester) async {
    var added = false;
    await _pump(tester, onAddProfile: ({required name, required watchTogetherName, required token}) async => added = true);

    await tester.tap(find.byType(AppCard).last);
    await tester.pump();
    expect(find.text('NEW PROFILE'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(find.text('NEW PROFILE'), findsNothing);
    expect(added, isFalse);
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
