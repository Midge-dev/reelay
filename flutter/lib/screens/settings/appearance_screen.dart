import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/neon_scrollbar.dart';

RoundedRectangleBorder _rowShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
final _rowColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
final _rowBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Screen 22 — "Applies to every screen · takes effect at once": there is no
/// Save button here, unlike the rest of Settings. Selecting a row persists
/// and applies immediately (see [onSelect]), matching the mockup's own copy.
class AppearanceScreen extends StatelessWidget {
  final ThemeId current;
  final ValueChanged<ThemeId> onSelect;
  final VoidCallback onBack;
  final FocusNode backFocus;

  const AppearanceScreen({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onBack,
    required this.backFocus,
  });

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.all(48.du(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 24.du(context)),
                    child: FocusableSurface(
                      onClick: onBack,
                      focusNode: backFocus,
                      shape: const StadiumBorder(),
                      colors: SurfaceColors(
                        container: AppColors.transparent,
                        content: AppColors.ink3,
                      ),
                      child: AppText('‹ Settings', color: AppColors.ink3),
                    ),
                  ),
                  AppText('Appearance', style: AppTypography.title1),
                  Padding(
                    padding: EdgeInsets.only(top: 8.du(context), bottom: 24.du(context)),
                    child: AppText(
                      'Applies to every screen · takes effect at once',
                      color: AppColors.ink3,
                    ),
                  ),
                  for (final id in ThemeId.values)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.du(context)),
                      child: _ThemeRow(
                        id: id,
                        selected: id == current,
                        onClick: () => onSelect(id),
                        autofocus: id == current,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48.du(context), horizontal: 12.du(context)),
            child: NeonScrollbar(controller: scrollController),
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ThemeId id;
  final bool selected;
  final bool autofocus;
  final VoidCallback onClick;

  const _ThemeRow({
    required this.id,
    required this.selected,
    required this.autofocus,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final palette = nocturnePalette(id);
    return SizedBox(
      height: 96.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        autofocus: autofocus,
        shape: _rowShape(context),
        colors: _rowColors,
        border: _rowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(id.label, style: AppTypography.label),
                    SizedBox(height: 2.du(context)),
                    AppText(
                      id.blurb,
                      style: AppTypography.caption,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              _Swatches(palette: palette),
              SizedBox(width: AppSpacing.lg.du(context)),
              SizedBox(
                width: 44.du(context),
                height: 44.du(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
                    border: Border.all(
                      color: palette.accent,
                      width: AppShape.borderWidth.du(context),
                    ),
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              SizedBox(
                width: 26.du(context),
                child: selected
                    ? AppIcon(
                        PhosphorIconsFill.checkCircle,
                        size: 26,
                        tint: AppColors.accent300,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The theme's six mockup-given swatches, in the same left-to-right order
/// as the design handoff's own preview strip: ground, surface, raised,
/// line, muted, accent.
class _Swatches extends StatelessWidget {
  final NocturnePalette palette;

  const _Swatches({required this.palette});

  @override
  Widget build(BuildContext context) {
    final colors = [
      palette.background,
      palette.surface,
      palette.surfaceRaised,
      palette.line,
      palette.ink3,
      palette.accent,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, color) in colors.indexed)
          Container(
            width: 24.du(context),
            height: 24.du(context),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.horizontal(
                left: index == 0 ? Radius.circular(4.du(context)) : Radius.zero,
                right: index == colors.length - 1
                    ? Radius.circular(4.du(context))
                    : Radius.zero,
              ),
            ),
          ),
      ],
    );
  }
}
