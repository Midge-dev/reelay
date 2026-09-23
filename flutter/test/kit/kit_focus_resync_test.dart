import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/kit/focusable_surface.dart';
import 'package:reelay/kit/surface_style.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  testWidgets('a surface re-created around an already-focused node paints focused', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    Widget build({required bool insertAbove}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          if (insertAbove) const SizedBox(height: 10),
          FocusableSurface(
            focusNode: node,
            onClick: () {},
            shape: const RoundedRectangleBorder(),
            colors: SurfaceColors(container: AppColors.surface, content: AppColors.ink2, focusedContainer: AppColors.surfaceRaised),
            child: const SizedBox(width: 10, height: 10),
          ),
        ],
      ),
    );
    await tester.pumpWidget(build(insertAbove: false));
    node.requestFocus();
    await tester.pumpAndSettle();
    // Content arriving above re-creates the surface's element.
    await tester.pumpWidget(build(insertAbove: true));
    await tester.pumpAndSettle();

    final decorated = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((decorated.decoration! as ShapeDecoration).color, AppColors.surfaceRaised);
  });
}
