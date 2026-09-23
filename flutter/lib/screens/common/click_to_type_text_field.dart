import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../focus/back_handler.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _borderWidth = 3.0;

/// A text field that stays read-only (D-pad-navigable, not text-editing)
/// until D-pad select is pressed, since a TV remote has no physical
/// keyboard.
///
/// A focused text field consumes Right for cursor movement before focus
/// traversal ever sees it, and Flutter's key dispatch starts at the focused
/// leaf and bubbles outward, so no ancestor can pre-empt EditableText's own
/// key handling. So this swaps between two widgets instead of toggling one
/// field's readOnly flag: a
/// plain focusable label (which has no text-field key handling to fight)
/// while not editing, and a real EditableText only once editing starts —
/// sidestepping the interception problem rather than solving it, valid
/// specifically because arrow-key cursor movement while *actually* typing
/// is correct behavior, not a bug to work around.
class ClickToTypeTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onValueChange;
  final TextStyle? textStyle;
  final VoidCallback? onNavigateRight;
  final FocusNode? focusNode;
  // Shown, in ink3, in place of the value when empty and not being edited —
  // opt-in since most callers (e.g. profile name fields) want a blank box.
  final String? hintText;

  /// False when the caller frames the field itself (the library's filter
  /// bar draws it as a chip) — the caller then reads focus from
  /// [onFocusChange] to paint its own focus signal.
  final bool showBorder;
  final ValueChanged<bool>? onFocusChange;

  const ClickToTypeTextField({
    super.key,
    required this.value,
    required this.onValueChange,
    this.textStyle,
    this.onNavigateRight,
    this.focusNode,
    this.hintText,
    this.showBorder = true,
    this.onFocusChange,
  });

  @override
  State<ClickToTypeTextField> createState() => _ClickToTypeTextFieldState();
}

class _ClickToTypeTextFieldState extends State<ClickToTypeTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late FocusNode _displayFocusNode;
  bool _ownsFocusNode = false;
  final _editFocusNode = FocusNode(debugLabel: 'click-to-type-edit');
  bool _editingEnabled = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _displayFocusNode =
        widget.focusNode ?? FocusNode(debugLabel: 'click-to-type-display');
    _displayFocusNode.addListener(_handleDisplayFocusChange);
    _editFocusNode.addListener(_handleEditFocusChange);
  }

  @override
  void didUpdateWidget(covariant ClickToTypeTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  void _handleDisplayFocusChange() {
    if (!mounted) return;
    setState(() => _isFocused = _displayFocusNode.hasFocus);
    widget.onFocusChange?.call(_isFocused || _editFocusNode.hasFocus);
  }

  void _handleEditFocusChange() {
    if (!mounted) return;
    widget.onFocusChange?.call(
      _displayFocusNode.hasFocus || _editFocusNode.hasFocus,
    );
    if (!_editFocusNode.hasFocus && _editingEnabled) {
      setState(() => _editingEnabled = false);
    }
  }

  @override
  void dispose() {
    _displayFocusNode.removeListener(_handleDisplayFocusChange);
    if (_ownsFocusNode) _displayFocusNode.dispose();
    _editFocusNode.removeListener(_handleEditFocusChange);
    _editFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _handleDisplayKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      setState(() => _editingEnabled = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _editFocusNode.requestFocus(),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        widget.onNavigateRight != null) {
      widget.onNavigateRight!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _stopEditing() {
    setState(() => _editingEnabled = false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _displayFocusNode.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always a role from the type scale — an unsized TextStyle falls back
    // to the framework's 14 logical px, which is neither a role nor scaled.
    final baseStyle = widget.textStyle ?? AppTypography.label;
    final style = baseStyle.copyWith(
      fontSize: baseStyle.fontSize?.du(context),
      letterSpacing: baseStyle.letterSpacing?.du(context),
    );
    final borderColor = _isFocused || _editingEnabled
        ? AppColors.accent
        : AppColors.line;

    return Container(
      decoration: widget.showBorder
          ? BoxDecoration(
              border: Border.all(
                color: borderColor,
                width: _borderWidth.du(context),
              ),
            )
          : null,
      child: _editingEnabled
          ? BackHandler(
              onBack: _stopEditing,
              child: EditableText(
                controller: _controller,
                focusNode: _editFocusNode,
                style: style,
                cursorColor: AppColors.accent,
                backgroundCursorColor: AppColors.surface,
                autofocus: true,
                onChanged: widget.onValueChange,
                onEditingComplete: _stopEditing,
                onSubmitted: (_) => _stopEditing(),
              ),
            )
          : Focus(
              focusNode: _displayFocusNode,
              onKeyEvent: _handleDisplayKeyEvent,
              child: widget.value.isEmpty && widget.hintText != null
                  ? Text(
                      widget.hintText!,
                      style: style.copyWith(color: AppColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      widget.value,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
    );
  }
}
