import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/neon_scrollbar.dart';

final RegExp _missingSpaceAfterAmpersand = RegExp(r'&(?=\S)');

String formatGenreLabel(String genre) => genre.replaceAllMapped(_missingSpaceAfterAmpersand, (_) => '& ');

/// The library filter row's applied-value chip (screen 18: "1990s ✕",
/// accent900 fill/accent300 text) — distinct from a dropdown's own applied
/// row treatment, which lives in [MenuOptionRow] below.
class AppliedValueChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const AppliedValueChip({super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FocusableSurface(
        onClick: onRemove,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.radiusMd)),
        colors: SurfaceColors(
          container: AppColors.accent900,
          content: AppColors.accent300,
          focusedContainer: AppColors.surfaceRaised,
          focusedContent: AppColors.ink,
          selectedContainer: AppColors.accent900,
          selectedContent: AppColors.accent300,
        ),
        border: const SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(label),
              const SizedBox(width: 12),
              const AppIcon(PhosphorIconsRegular.x, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

final _menuShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShape.radiusMd));
final _menuRowColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surface,
  selectedContent: AppColors.ink,
);
const _menuRowBorder = SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent));

class MenuOptionRow extends StatelessWidget {
  final String label;
  final String? countLabel;
  final bool applied;
  final bool dimmed;
  final VoidCallback onClick;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  const MenuOptionRow({
    super.key,
    required this.label,
    this.countLabel,
    required this.applied,
    this.dimmed = false,
    required this.onClick,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = dimmed
        ? SurfaceColors(
            container: _menuRowColors.container,
            content: _menuRowColors.content.withValues(alpha: 0.5),
            focusedContainer: _menuRowColors.focusedContainer,
            focusedContent: _menuRowColors.focusedContent.withValues(alpha: 0.5),
            selectedContainer: _menuRowColors.selectedContainer,
            selectedContent: _menuRowColors.selectedContent.withValues(alpha: 0.5),
          )
        : _menuRowColors;

    return SizedBox(
      height: 64,
      child: FocusableSurface(
        onClick: onClick,
        selected: applied,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        shape: _menuShape,
        colors: colors,
        border: _menuRowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(child: AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (countLabel != null) ...[
                const SizedBox(width: 12),
                AppText(countLabel!, color: dimmed ? AppColors.ink3.withValues(alpha: 0.5) : AppColors.ink3),
              ],
              if (applied) ...[const SizedBox(width: 12), const AppIcon(PhosphorIconsFill.checkCircle, size: 22)],
            ],
          ),
        ),
      ),
    );
  }
}

/// One option inside a [FilterDropdown].
class FilterOption {
  final String label;
  final String? countLabel;
  final bool applied;
  final bool dimmed;

  const FilterOption({required this.label, this.countLabel, required this.applied, this.dimmed = false});
}

/// A single-topic floating filter dropdown (screen 18: "GENRE · 18 IN THIS
/// LIBRARY") — one of these opens from whichever chip triggered it (Genre,
/// Decade, Added or Sort), replacing the old fused genre+decade+added side
/// panel now that each filter gets its own chip in one row (screen 17's
/// note: "not a separate tab"). Selecting the already-applied option clears
/// it — the D-pad-appropriate equivalent of the mockup's pointer-driven "✕"
/// on an applied value chip, which stays in the filter row itself.
class FilterDropdown extends StatefulWidget {
  final String title;
  final List<FilterOption> options;
  final ValueChanged<int> onSelect;
  final FocusNode aboveFocusNode;
  final String footerHint;

  const FilterDropdown({
    super.key,
    required this.title,
    required this.options,
    required this.onSelect,
    required this.aboveFocusNode,
    this.footerHint = 'Select toggles · Back closes and keeps what you picked',
  });

  @override
  State<FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<FilterDropdown> {
  final _scrollController = ScrollController();
  int _highlightedIndex = 0;
  late List<FocusNode> _rowFocusNodes = List.generate(widget.options.length, (i) => FocusNode(debugLabel: 'filter-dropdown-row-$i'));

  @override
  void didUpdateWidget(covariant FilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      for (final node in _rowFocusNodes) {
        node.dispose();
      }
      _rowFocusNodes = List.generate(widget.options.length, (i) => FocusNode(debugLabel: 'filter-dropdown-row-$i'));
      if (_highlightedIndex >= widget.options.length) {
        _highlightedIndex = widget.options.isEmpty ? 0 : widget.options.length - 1;
      }
    }
  }

  @override
  void dispose() {
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handlePanelKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _highlightedIndex == widget.options.length - 1) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _highlightedIndex == 0) {
      widget.aboveFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      constraints: const BoxConstraints(maxHeight: 520),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(AppShape.radiusLg),
        boxShadow: AppElevation.overlay,
      ),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handlePanelKeyEvent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(widget.title, style: AppTypography.micro, color: AppColors.accent300),
            const SizedBox(height: 10),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      clipBehavior: Clip.none,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (index, option) in widget.options.indexed) ...[
                            MenuOptionRow(
                              label: option.label,
                              countLabel: option.countLabel,
                              applied: option.applied,
                              dimmed: option.dimmed,
                              onClick: () => widget.onSelect(index),
                              focusNode: _rowFocusNodes[index],
                              onFocusChange: (focused) {
                                if (focused) setState(() => _highlightedIndex = index);
                              },
                            ),
                            const SizedBox(height: 2),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeonScrollbar(controller: _scrollController),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.lineStrong))),
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: AppText(widget.footerHint, color: AppColors.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
