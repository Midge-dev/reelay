import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/focusable_surface.dart';
import 'package:reelay/kit/surface_style.dart';

SurfaceColors _testColors() => SurfaceColors(
      container: const Color(0xFF000001),
      content: const Color(0xFF000002),
      focusedContainer: const Color(0xFF000003),
      focusedContent: const Color(0xFF000004),
      pressedContainer: const Color(0xFF000005),
      pressedContent: const Color(0xFF000006),
      selectedContainer: const Color(0xFF000007),
      selectedContent: const Color(0xFF000008),
      disabledContainer: const Color(0xFF000009),
      disabledContent: const Color(0xFF00000A),
    );

Color? _decorationColor(WidgetTester tester) {
  final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
  return (decoratedBox.decoration as ShapeDecoration).color;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));
}

void main() {
  testWidgets('idle state uses the base container color', (tester) async {
    await _pump(
      tester,
      FocusableSurface(
        onClick: () {},
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );

    expect(_decorationColor(tester), const Color(0xFF000001));
  });

  testWidgets('gaining focus switches to the focused container color', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pump(
      tester,
      FocusableSurface(
        onClick: () {},
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue, reason: 'sanity check the FocusNode itself before inspecting rendering');
    expect(_decorationColor(tester), const Color(0xFF000003));
  });

  testWidgets('selected state is used only when not focused', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pump(
      tester,
      FocusableSurface(
        onClick: () {},
        selected: true,
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );

    expect(_decorationColor(tester), const Color(0xFF000007), reason: 'selected, not focused');

    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();

    expect(_decorationColor(tester), const Color(0xFF000003), reason: 'focus takes precedence over selected');
  });

  testWidgets('disabled takes precedence over every other state', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await _pump(
      tester,
      FocusableSurface(
        onClick: () {},
        enabled: false,
        selected: true,
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(_decorationColor(tester), const Color(0xFF000009));
  });

  testWidgets('a select-key press invokes onClick on key-up, not key-down', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var clicks = 0;

    await _pump(
      tester,
      FocusableSurface(
        onClick: () => clicks++,
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(clicks, 0, reason: 'click fires on release, not press');
    expect(_decorationColor(tester), const Color(0xFF000005), reason: 'pressed color while held');

    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(clicks, 1);
  });

  testWidgets('a disabled surface cannot be focused, so it is skipped by D-pad traversal', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var clicks = 0;

    await _pump(
      tester,
      FocusableSurface(
        onClick: () => clicks++,
        enabled: false,
        focusNode: focusNode,
        shape: const RoundedRectangleBorder(),
        colors: _testColors(),
        child: const SizedBox(width: 10, height: 10),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
    expect(clicks, 0);
  });
}
