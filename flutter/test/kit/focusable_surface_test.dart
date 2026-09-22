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
    );

Color? _decorationColor(WidgetTester tester) {
  // Selected-and-focused adds a small ink-dot indicator (its own Container,
  // hence its own DecoratedBox) on top of the surface's — take the surface's
  // own, which paints first.
  final decoratedBox = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).first;
  return (decoratedBox.decoration as ShapeDecoration).color;
}

double _opacity(WidgetTester tester) {
  final opacity = tester.widgetList<Opacity>(find.byType(Opacity));
  return opacity.isEmpty ? 1.0 : opacity.first.opacity;
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(_decorationColor(tester), const Color(0xFF000003), reason: 'focus takes precedence over selected');
  });

  testWidgets('disabled renders the idle appearance at 45% opacity, not a separate color', (tester) async {
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
    await tester.pumpAndSettle();

    expect(_decorationColor(tester), const Color(0xFF000001), reason: 'disabled ignores selected/focused and shows the idle container');
    expect(_opacity(tester), 0.45);
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
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
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
