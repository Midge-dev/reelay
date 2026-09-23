import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../kit/button.dart';

RoundedRectangleBorder _rowShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
SurfaceColors get _rowColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _rowBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Screen 22 — the theme list shown in Settings' Appearance pane. Each
/// row carries the ramp itself (ground → accent) and, on the right, a
/// focused surface drawn in that theme — "the one state worth judging a
/// palette by on a television". Selecting applies and persists at once.
class ThemeList extends StatelessWidget {
  final ThemeId current;
  final ValueChanged<ThemeId> onSelect;
  final FocusNode? currentFocus;

  const ThemeList({super.key, required this.current, required this.onSelect, this.currentFocus});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, id) in ThemeId.values.indexed) ...[
          if (i > 0) SizedBox(height: AppSpacing.md.du(context)),
          _ThemeRow(
            id: id,
            selected: id == current,
            focusNode: id == current ? currentFocus : null,
            onClick: () => onSelect(id),
          ),
        ],
      ],
    );
  }
}

/// The "UI Size" control — a stepper, not a drag slider, since there's no
/// pointer on a D-pad remote. Steps by [AppSettings.uiScaleStep] and snaps
/// to that grid on every change (rather than drifting on floating-point
/// arithmetic across repeated presses), clamped to
/// [AppSettings.minUiScale]/[AppSettings.maxUiScale].
class UiScaleStepper extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const UiScaleStepper({super.key, required this.value, required this.onChanged});

  double _snap(double v) {
    final stepped = (v / AppSettings.uiScaleStep).round() * AppSettings.uiScaleStep;
    return stepped.clamp(AppSettings.minUiScale, AppSettings.maxUiScale);
  }

  @override
  Widget build(BuildContext context) {
    final canDecrease = value > AppSettings.minUiScale;
    final canIncrease = value < AppSettings.maxUiScale;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          enabled: canDecrease,
          onClick: () => onChanged(_snap(value - AppSettings.uiScaleStep)),
          child: const AppIcon(PhosphorIconsRegular.minus, size: 22),
        ),
        SizedBox(
          width: 110.du(context),
          child: Center(
            child: AppText(
              '${(value * 100).round()}%',
              style: AppTypography.rowLabel.copyWith(fontFeatures: AppTypography.tabular),
            ),
          ),
        ),
        AppIconButton(
          enabled: canIncrease,
          onClick: () => onChanged(_snap(value + AppSettings.uiScaleStep)),
          child: const AppIcon(PhosphorIconsRegular.plus, size: 22),
        ),
        if (value != AppSettings.defaultUiScale) ...[
          SizedBox(width: AppSpacing.lg.du(context)),
          AppGhostButton(
            onClick: () => onChanged(AppSettings.defaultUiScale),
            child: AppText('Reset to ${(AppSettings.defaultUiScale * 100).round()}%', style: AppTypography.caption, color: null),
          ),
        ],
      ],
    );
  }
}

class _ThemeRow extends StatefulWidget {
  final ThemeId id;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _ThemeRow({required this.id, required this.selected, this.focusNode, required this.onClick});

  @override
  State<_ThemeRow> createState() => _ThemeRowState();
}

class _ThemeRowState extends State<_ThemeRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final palette = nocturnePalette(id);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 86.du(context)),
      child: FocusableSurface(
        onClick: widget.onClick,
        selected: widget.selected,
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        shape: _rowShape(context),
        colors: _rowColors,
        border: _rowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22.du(context), vertical: AppSpacing.md.du(context)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      id.label,
                      style: AppTypography.body.copyWith(height: 1.3, fontWeight: _focused ? FontWeight.w500 : FontWeight.w400),
                      color: _focused ? AppColors.ink : AppColors.ink2,
                    ),
                    SizedBox(height: 2.du(context)),
                    AppText(id.blurb, style: AppTypography.caption, color: _focused ? AppColors.ink2 : AppColors.ink3),
                  ],
                ),
              ),
              SizedBox(width: 22.du(context)),
              _Swatches(palette: palette),
              SizedBox(width: 22.du(context)),
              Container(
                width: 70.du(context),
                height: 44.du(context),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
                  border: Border.all(color: palette.accent, width: AppShape.borderWidth.du(context)),
                ),
              ),
              SizedBox(width: 22.du(context)),
              SizedBox(
                width: 26.du(context),
                child: widget.selected
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
            width: 30.du(context),
            height: 30.du(context),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.horizontal(
                left: index == 0 ? Radius.circular(5.du(context)) : Radius.zero,
                right: index == colors.length - 1
                    ? Radius.circular(5.du(context))
                    : Radius.zero,
              ),
            ),
          ),
      ],
    );
  }
}
