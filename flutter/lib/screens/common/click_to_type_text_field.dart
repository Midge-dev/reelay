import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../focus/back_handler.dart';
import '../../theme/tokens.dart';

const _borderWidth = 3.0;

/// Ports ui/common/KeyboardOnSelect.kt's `ClickToTypeTextField` — stays
/// read-only (D-pad-navigable, not text-editing) until D-pad select is
/// pressed, since a TV remote has no physical keyboard.
///
/// The Kotlin version toggles `readOnly` on one continuously-focused
/// BasicTextField, needing an `onPreviewKeyEvent` workaround because a
/// focused text field consumes DirectionRight for cursor movement before
/// Compose's own focus-search or Flutter's key-event bubbling would ever
/// see it (see feedback_textfield_dpad_capture — the same root cause
/// applies to Flutter's EditableText). Flutter's key dispatch starts at
/// the focused leaf and bubbles outward, so an ancestor can never truly
/// pre-empt EditableText's own internal key handling the way Compose's
/// tunneling `onPreviewKeyEvent` can. This ports the same UX by swapping
/// between two widgets instead of toggling one field's readOnly flag: a
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

  const ClickToTypeTextField({
    super.key,
    required this.value,
    required this.onValueChange,
    this.textStyle,
    this.onNavigateRight,
    this.focusNode,
  });

  @override
  State<ClickToTypeTextField> createState() => _ClickToTypeTextFieldState();
}

class _ClickToTypeTextFieldState extends State<ClickToTypeTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  late FocusNode _displayFocusNode;
  bool _ownsFocusNode = false;
  final _editFocusNode = FocusNode(debugLabel: 'click-to-type-edit');
  bool _editingEnabled = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _displayFocusNode = widget.focusNode ?? FocusNode(debugLabel: 'click-to-type-display');
    _displayFocusNode.addListener(_handleDisplayFocusChange);
    _editFocusNode.addListener(_handleEditFocusChange);
  }

  @override
  void didUpdateWidget(covariant ClickToTypeTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  void _handleDisplayFocusChange() {
    if (!mounted) return;
    setState(() => _isFocused = _displayFocusNode.hasFocus);
  }

  void _handleEditFocusChange() {
    if (!mounted) return;
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
    if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter) {
      setState(() => _editingEnabled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _editFocusNode.requestFocus());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onNavigateRight != null) {
      widget.onNavigateRight!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _stopEditing() {
    setState(() => _editingEnabled = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _displayFocusNode.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.textStyle ?? const TextStyle(fontFamily: 'Inter', color: AppColors.ink);
    final borderColor = _isFocused || _editingEnabled ? AppColors.accent : AppColors.line;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: _borderWidth),
      ),
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
              child: Text(widget.value, style: style),
            ),
    );
  }
}
