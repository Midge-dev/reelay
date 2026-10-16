import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/screens/common/click_to_type_text_field.dart';
import 'package:reelay/screens/profiles/add_profile_dialog.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> _pump(
  WidgetTester tester, {
  CreateProfile? onCreate,
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
      // The app's arrow-key traversal, which WidgetsApp would provide.
      child: Shortcuts(
        shortcuts: WidgetsApp.defaultShortcuts,
        child: Actions(
          actions: WidgetsApp.defaultActions,
          child: Stack(
            children: [
              AddProfileDialog(
                onCreate: onCreate ?? ({required name, required watchTogetherName, token, jellyfin}) async {},
                onCancel: onCancel ?? () {},
                linkPanelBuilder: linkPanelBuilder,
              ),
            ],
          ),
        ),
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
    expect(find.text('Sign in'), findsNWidgets(2), reason: 'Plex and Jellyfin');
    expect(find.text('ACCOUNTS'), findsOneWidget, reason: 'no name typed yet');
  });

  testWidgets('Jellyfin is a live sign-in beside Plex', (tester) async {
    await _pump(tester);

    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('COMING SOON'), findsNothing);
    expect(find.text('They sign in with their own Jellyfin account'), findsOneWidget);
    expect(find.text('They sign in with their own Plex account'), findsOneWidget);

    await _typeName(tester, 'Sam');
    expect(find.text('Sam signs in with their own Jellyfin account'), findsOneWidget);
  });

  testWidgets('Jellyfin\'s Sign in opens the link screen over the dialog, and Back returns to it', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await _pump(tester);
    await _typeName(tester, 'Sam');

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('NEW PROFILE · SAM · JELLYFIN'), findsOneWidget);
    expect(find.text('Fill this in from your phone'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text("Who's joining this device?"), findsOneWidget);
    expect(find.text("SAM'S ACCOUNTS"), findsOneWidget, reason: 'the typed name survives the trip');
  });

  testWidgets('Down from the name reaches each sign-in, Plex then Jellyfin', (tester) async {
    await _pump(tester);
    final name = tester.widget<ClickToTypeTextField>(find.byType(ClickToTypeTextField).first);
    name.focusNode!.requestFocus();
    await tester.pump();

    /// The account row holding focus, by its platform name.
    String? focusedRow() {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return null;
      Widget? card = focused.widget is AppCard ? focused.widget : null;
      focused.visitAncestorElements((e) {
        if (e.widget is! AppCard) return true;
        card ??= e.widget;
        return false;
      });
      if (card == null) return 'focus on ${focused.widget.runtimeType}';
      for (final platform in ['Plex', 'Jellyfin']) {
        if (find.descendant(of: find.byWidget(card!), matching: find.text(platform)).evaluate().isNotEmpty) {
          return platform;
        }
      }
      return null;
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedRow(), 'Plex');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedRow(), 'Jellyfin');
  });

  testWidgets('once it can be created, Down from the last account is Create profile', (tester) async {
    await _pump(tester, linkPanelBuilder: (onLinked) => _FakeLinkPanel(onLinked: onLinked));
    await _typeName(tester, 'Sam');
    await tester.tap(find.text('Sign in').first);
    await tester.pump();
    await tester.tap(find.text('link now'));
    await tester.pump();

    final jellyfinRow = find.ancestor(of: find.text('Jellyfin'), matching: find.byType(AppCard));
    Focus.of(tester.element(find.descendant(of: jellyfinRow, matching: find.text('Jellyfin')))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byWidget(focused.widget), matching: find.text('Create profile')), findsOneWidget);
  });

  testWidgets('typing a name updates the accounts kicker', (tester) async {
    await _pump(tester);

    await _typeName(tester, 'Sam');

    expect(find.text("SAM'S ACCOUNTS"), findsOneWidget);
  });

  testWidgets('tapping Sign in shows the link panel and hides the Sign in button', (tester) async {
    await _pump(tester, linkPanelBuilder: (onLinked) => const Text('linking...'));

    await tester.tap(find.text('Sign in').first);
    await tester.pump();

    expect(find.text('linking...'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget, reason: 'only Jellyfin\'s is left');
  });

  testWidgets('Create profile is a no-op until both a name and a linked account exist', (tester) async {
    var created = false;
    await _pump(
      tester,
      onCreate: ({required name, required watchTogetherName, token, jellyfin}) async => created = true,
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

  testWidgets('Create profile invokes onCreate with the typed name and linked token once both are ready', (
    tester,
  ) async {
    String? createdName;
    String? createdWatchTogetherName;
    String? createdToken;
    await _pump(
      tester,
      onCreate: ({required name, required watchTogetherName, token, jellyfin}) async {
        createdName = name;
        createdWatchTogetherName = watchTogetherName;
        createdToken = token;
      },
      linkPanelBuilder: (onLinked) => _FakeLinkPanel(onLinked: onLinked),
    );

    await _typeName(tester, 'Sam');
    await tester.tap(find.text('Sign in').first);
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
    return GestureDetector(onTap: () => onLinked('fake-token'), child: const Text('link now'));
  }
}
