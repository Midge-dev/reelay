import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../common/neon_scrollbar.dart';

/// A scrollable
/// dropdown. Checklist item #8 (a menu's own internal navigation must not
/// be misread as the user backing out): Left/Right never leave the menu,
/// and Up/Down stop at the first/last row — it tracks which row is
/// highlighted and swallows any arrow key that would carry focus past the
/// menu's own bounds.
class MaxSeatsMenu extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const MaxSeatsMenu({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<MaxSeatsMenu> createState() => _MaxSeatsMenuState();
}

const _rowHeight = 46.0;
const _rowSpacing = 2.0;
const _maxMenuHeight = 320.0;

class _MaxSeatsMenuState extends State<MaxSeatsMenu> {
  late int _highlightedIndex = AppSettings.maxHostSeatsOptions
      .indexOf(widget.selected)
      .clamp(0, AppSettings.maxHostSeatsOptions.length - 1);
  final _scrollController = ScrollController();
  final _rowFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < AppSettings.maxHostSeatsOptions.length; i++) {
      _rowFocusNodes.add(FocusNode(debugLabel: 'max-seats-$i'));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_highlightedIndex < _rowFocusNodes.length)
        _rowFocusNodes[_highlightedIndex].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _rowFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleMenuKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final options = AppSettings.maxHostSeatsOptions;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _highlightedIndex == 0) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _highlightedIndex == options.length - 1) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final options = AppSettings.maxHostSeatsOptions;
    // A definite height (matching the rows' own natural content height, up
    // to a cap) for crossAxisAlignment.stretch to stretch the scrollbar
    // into — without it, the Row's height is unbounded (this whole menu
    // sits in a Positioned with no top+bottom), and stretch demanding an
    // infinite height throws a caught-but-fatal layout exception, which
    // silently renders nothing rather than crashing: the menu becomes
    // fully invisible. Computed directly rather than via IntrinsicHeight,
    // which doesn't work here — Viewport-based widgets like ListView
    // explicitly don't support intrinsic-dimension queries and throw their
    // own layout error when asked, the exact same invisible-menu failure
    // this whole computation exists to avoid.
    final rowHeight = _rowHeight.du(context);
    final rowSpacing = _rowSpacing.du(context);
    final naturalHeight =
        options.length * rowHeight + (options.length - 1) * rowSpacing;
    final menuHeight = naturalHeight.clamp(0.0, _maxMenuHeight.du(context));
    return Container(
      width: 300.du(context),
      padding: EdgeInsets.all(12.du(context)),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8.du(context)),
      ),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleMenuKeyEvent,
        child: SizedBox(
          height: menuHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: options.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: rowSpacing),
                  itemBuilder: (context, index) {
                    final value = options[index];
                    final applied = value == widget.selected;
                    return _MaxSeatsRow(
                      value: value,
                      applied: applied,
                      focusNode: _rowFocusNodes[index],
                      onFocusChange: (focused) {
                        if (focused) setState(() => _highlightedIndex = index);
                      },
                      onClick: () => widget.onSelect(value),
                    );
                  },
                ),
              ),
              SizedBox(width: 8.du(context)),
              NeonScrollbar(controller: _scrollController),
            ],
          ),
        ),
      ),
    );
  }
}

RoundedRectangleBorder _rowShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8.du(context))),
    );
SurfaceColors get _rowColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.inkOnArt,
  focusedContainer: AppColors.accent,
  selectedContainer: AppColors.accent.withValues(alpha: 0.35),
);
SurfaceBorder get _rowBorder =>
    SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent));

class _MaxSeatsRow extends StatelessWidget {
  final int value;
  final bool applied;
  final FocusNode focusNode;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onClick;

  const _MaxSeatsRow({
    required this.value,
    required this.applied,
    required this.focusNode,
    required this.onFocusChange,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: applied,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        shape: _rowShape(context),
        colors: _rowColors,
        border: _rowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.du(context)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16.du(context),
                child: applied ? const AppText('✓') : null,
              ),
              SizedBox(width: 12.du(context)),
              AppText('$value'),
            ],
          ),
        ),
      ),
    );
  }
}
