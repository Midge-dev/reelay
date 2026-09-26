import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../focus/back_handler.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/app_state.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../navigation/rail_order.dart';

/// The nav rail's movable items, in rail order, for reordering with the
/// remote: Select picks a row up, Up/Down carries it, Select or Back puts
/// it down. There's no drag on a D-pad, so moving is a mode, and while a
/// row is held Left/Right do nothing rather than walk focus out of the
/// pane with it.
class RailOrderList extends StatefulWidget {
  /// Resolved order (see [resolveRailOrder]).
  final List<String> order;
  final List<SectionGroup> sections;
  final ValueChanged<List<String>> onChanged;

  const RailOrderList({
    super.key,
    required this.order,
    required this.sections,
    required this.onChanged,
  });

  @override
  State<RailOrderList> createState() => _RailOrderListState();
}

class _RailOrderListState extends State<RailOrderList> {
  /// The row being carried, if any.
  String? _moving;

  /// One node per item id, so focus stays on a row as it changes place.
  final _nodes = <String, FocusNode>{};

  FocusNode _node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'rail-order-$id'));

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _key(String id, KeyEvent event) {
    if (_moving != id) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      widget.onChanged(moveRailItem(widget.order, id, delta));
      // Keep the carried row in view as it passes the pane's edge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _nodes[id]?.context;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(
            row,
            alignmentPolicy: delta < 0
                ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
                : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggle(String id) =>
      setState(() => _moving = _moving == id ? null : id);

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      enabled: _moving != null,
      onBack: () => setState(() => _moving = null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, id) in widget.order.indexed)
            if (railItemLook(id, widget.sections) case final look?) ...[
              if (i > 0) SizedBox(height: AppSpacing.sm.du(context)),
              // Keys bubble up from the row's own node to this one, which
              // takes no focus itself.
              Focus(
                key: ValueKey(id),
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, event) => _key(id, event),
                child: _RailOrderRow(
                  look: look,
                  moving: _moving == id,
                  focusNode: _node(id),
                  onClick: () => _toggle(id),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _RailOrderRow extends StatefulWidget {
  final RailItemLook look;
  final bool moving;
  final FocusNode focusNode;
  final VoidCallback onClick;

  const _RailOrderRow({
    required this.look,
    required this.moving,
    required this.focusNode,
    required this.onClick,
  });

  @override
  State<_RailOrderRow> createState() => _RailOrderRowState();
}

class _RailOrderRowState extends State<_RailOrderRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final moving = widget.moving;
    final ink = _focused || moving ? AppColors.ink : AppColors.ink2;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 72.du(context)),
      child: FocusableSurface(
        onClick: widget.onClick,
        selected: moving,
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        colors: SurfaceColors(
          container: AppColors.surface,
          content: AppColors.ink2,
          focusedContainer: AppColors.surfaceRaised,
          focusedContent: AppColors.ink,
          selectedContainer: AppColors.surfaceRaised,
          selectedContent: AppColors.ink,
        ),
        border: SurfaceBorder(
          idle: SurfaceBorderSide.solid(AppColors.line),
          focused: SurfaceBorderSide.solid(AppColors.accent),
        ),
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
          child: Row(
            children: [
              AppIcon(
                moving ? look.selectedIcon : look.icon,
                size: 24,
                tint: ink,
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              Expanded(
                child: AppText(
                  look.label,
                  style: AppTypography.body.copyWith(
                    fontWeight: _focused || moving
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  color: ink,
                  maxLines: 1,
                ),
              ),
              if (moving) ...[
                AppIcon(PhosphorIconsRegular.caretUp, size: 18, tint: ink),
                AppIcon(PhosphorIconsRegular.caretDown, size: 18, tint: ink),
                SizedBox(width: AppSpacing.sm.du(context)),
                AppText(
                  'Move, then OK to place',
                  style: AppTypography.caption,
                  color: AppColors.ink2,
                ),
              ] else if (_focused)
                AppText(
                  'OK to move',
                  style: AppTypography.caption,
                  color: AppColors.ink3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
