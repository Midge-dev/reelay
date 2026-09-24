import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/neon_scrollbar.dart';
import 'package:reelay/screens/library/genre_filter_panel.dart';

void main() {
  testWidgets('rows scrolled out of the list are clipped at its top, but the sides stay open for the focus scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final above = FocusNode();
    addTearDown(above.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FilterDropdown(
            title: 'GENRE · 30 IN THIS LIBRARY',
            aboveFocusNode: above,
            onSelect: (_) {},
            options: [for (var i = 0; i < 30; i++) FilterOption(label: 'Genre $i', applied: false)],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the scrollbar must paint without throwing');

    final firstRow = tester.getRect(find.text('Genre 0'));
    final clip = tester.renderObject<RenderClipRect>(
      find.ancestor(of: find.text('Genre 0'), matching: find.byType(ClipRect)).first,
    );
    final clipRect = MatrixUtils.transformRect(clip.getTransformTo(null), clip.clipper!.getClip(clip.size));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));

    expect(firstRow.bottom, lessThan(viewport.top), reason: 'scrolled up out of the list');
    expect(clipRect.top, viewport.top, reason: 'nothing paints above the list');
    expect(clipRect.bottom, viewport.bottom, reason: 'nothing paints below it');
    expect(clipRect.left, lessThan(viewport.left), reason: 'the focused row may grow past the sides');
    expect(clipRect.right, greaterThan(viewport.right));
  });

  testWidgets('the scrollbar runs the full height of a long list', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final above = FocusNode();
    addTearDown(above.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FilterDropdown(
            title: 'GENRE',
            aboveFocusNode: above,
            onSelect: (_) {},
            options: [for (var i = 0; i < 30; i++) FilterOption(label: 'Genre $i', applied: false)],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(NeonScrollbar)).height, tester.getSize(find.byType(SingleChildScrollView)).height);
  });

  testWidgets('a short list keeps the list short', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final above = FocusNode();
    addTearDown(above.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FilterDropdown(
            title: 'DECADE',
            aboveFocusNode: above,
            onSelect: (_) {},
            options: [for (var i = 0; i < 3; i++) FilterOption(label: 'Decade $i', applied: false)],
          ),
        ),
      ),
    );
    // Three 64 du rows (plus gaps and padding), not stretched to the
    // panel's 520 du maximum.
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, lessThan(250));
  });
}
