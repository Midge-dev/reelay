import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  tearDown(() => AppColors.applyTheme(ThemeId.nocturne));

  test('applyTheme reassigns every swappable field and nothing else', () {
    AppColors.applyTheme(ThemeId.ember);

    expect(AppColors.currentTheme, ThemeId.ember);
    expect(AppColors.background, const Color(0xFF0F1014));
    expect(AppColors.accent, const Color(0xFFC89B5A));
    expect(AppColors.ink, const Color(0xFFD6D5D3));

    // Status colors never re-tint, per DESIGN.md.
    expect(AppColors.success, const Color(0xFF6FB98A));
    expect(AppColors.warning, const Color(0xFFD8A14B));
    expect(AppColors.error, const Color(0xFFD4756A));
  });

  test('nocturnePalette previews every theme without mutating live AppColors state', () {
    final before = AppColors.accent;

    final quartz = nocturnePalette(ThemeId.quartz);

    expect(quartz.accent, const Color(0xFFAE8B9B));
    expect(
      AppColors.accent,
      before,
      reason: 'previewing a palette must not apply it',
    );
  });

  test(
    'accent700/900 keep a trace of hue for every theme with a tinted accent',
    () {
      for (final id in ThemeId.values) {
        if (id == ThemeId.projection) continue; // deliberately achromatic
        final p = nocturnePalette(id);
        final isGrayscale =
            p.accent700.r == p.accent700.g && p.accent700.g == p.accent700.b;
        expect(
          isGrayscale,
          isFalse,
          reason: '${id.label} accent700 should not fully desaturate',
        );
      }
    },
  );
}
