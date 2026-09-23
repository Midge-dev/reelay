import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/focus/back_handler.dart';

/// A page with its own BackHandler and, when [panelOpen], a panel over it
/// with another — the shape of the rooms panel / server switcher over a
/// detail page.
Widget _app({required bool panelOpen, required VoidCallback onPageBack, required VoidCallback onPanelBack, FocusNode? panelFocus, FocusNode? pageFocus, FocusNode? outsideFocus}) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (c, _, _) => builder(c)),
    home: Stack(
      children: [
        BackHandler(onBack: onPageBack, child: Focus(focusNode: pageFocus, child: const SizedBox(width: 10, height: 10))),
        Positioned(left: 50, child: Focus(focusNode: outsideFocus, child: const SizedBox(width: 10, height: 10))),
        if (panelOpen)
          Positioned(
            left: 100,
            child: BackHandler(onBack: onPanelBack, child: Focus(focusNode: panelFocus, child: const SizedBox(width: 10, height: 10))),
          ),
      ],
    ),
  );
}

void main() {
  testWidgets('Back with focus inside a panel closes only the panel, not the page under it', (tester) async {
    var page = 0, panel = 0;
    final panelFocus = FocusNode();
    addTearDown(panelFocus.dispose);
    await tester.pumpWidget(_app(panelOpen: true, onPageBack: () => page++, onPanelBack: () => panel++, panelFocus: panelFocus));
    panelFocus.requestFocus();
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(panel, 1);
    expect(page, 0);
  });

  testWidgets('Back with focus inside the page answers the page', (tester) async {
    var page = 0, panel = 0;
    final pageFocus = FocusNode();
    addTearDown(pageFocus.dispose);
    await tester.pumpWidget(_app(panelOpen: true, onPageBack: () => page++, onPanelBack: () => panel++, pageFocus: pageFocus));
    pageFocus.requestFocus();
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(page, 1);
    expect(panel, 0);
  });

  testWidgets('with focus outside every handler, the most recently mounted one answers', (tester) async {
    var page = 0, panel = 0;
    final outside = FocusNode();
    addTearDown(outside.dispose);
    await tester.pumpWidget(_app(panelOpen: true, onPageBack: () => page++, onPanelBack: () => panel++, outsideFocus: outside));
    outside.requestFocus();
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(panel, 1, reason: 'e.g. focus still on the rail item that opened the rooms panel');
    expect(page, 0);
  });
}
