import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// A full-bleed scrim confirm
/// dialog, layered on top of a card's still-mounted content (checklist
/// item #1's Stack-overlay pattern), not swapped in via if/else.
///
/// Two hazards it handles deliberately:
///
/// - **checklist item #3, cross-widget variant.** The long-press that
///   opens this overlay is still physically held when it appears;
///   RemoveConfirmOverlay immediately grabs focus onto Remove, so the
///   eventual key-up of that same press lands on Remove as a "bare"
///   KeyUpEvent with no KeyDownEvent of its own. Flutter's key
///   dispatch bubbles from the focused leaf outward (confirmed via
///   HardwareKeyboard.addHandler's source: its handlers run before the
///   focus-tree dispatch but don't gate/cancel it), so an ancestor can't
///   pre-empt a descendant FocusableSurface's own onClick. Handled instead
///   by guarding the *semantic action*: `_armed` starts false on every
///   fresh mount (this widget is freshly built each time it appears) and
///   the
///   first Confirm/Cancel activation only arms it; the action itself
///   requires a second, deliberate press.
/// - **Auto-dismiss on focus loss, correctly sequenced.** Only starts
///   watching for "focus left" after observing at least one genuine
///   focus-gained report — otherwise the single frame before the initial
///   requestFocus() lands would immediately auto-cancel the overlay it
///   just opened.
class RemoveConfirmOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool compact;

  const RemoveConfirmOverlay({
    super.key,
    required this.message,
    required this.onConfirm,
    required this.onCancel,
    this.compact = false,
  });

  @override
  State<RemoveConfirmOverlay> createState() => _RemoveConfirmOverlayState();
}

class _RemoveConfirmOverlayState extends State<RemoveConfirmOverlay> {
  final _removeFocus = FocusNode(debugLabel: 'remove-confirm-remove');
  final _cancelFocus = FocusNode(debugLabel: 'remove-confirm-cancel');
  bool _armed = false;
  bool _hasBeenFocusedSinceShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _removeFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _removeFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  void _handleRegionFocusChange(bool hasFocus) {
    if (hasFocus) {
      _hasBeenFocusedSinceShown = true;
    } else if (_hasBeenFocusedSinceShown) {
      widget.onCancel();
    }
  }

  void _guardedConfirm() {
    if (!_armed) {
      setState(() => _armed = true);
      return;
    }
    widget.onConfirm();
  }

  void _guardedCancel() {
    if (!_armed) {
      setState(() => _armed = true);
      return;
    }
    widget.onCancel();
  }

  // Remove/Cancel lay out as a Row when not compact (navigated with
  // left/right) and a Column when compact (navigated with up/down) — the
  // escape/edge traps below must swap axis to match, or the *only* axis
  // the buttons can actually be reached on ends up fully blocked instead
  // of just trapped at the true edge.
  KeyEventResult _trapEscape(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final escaping = widget.compact
        ? (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight)
        : (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown);
    return escaping ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  // Remove <-> Cancel is moved explicitly rather than left to directional
  // traversal: the host card's own focus node wraps this overlay and spans
  // the whole card, so geometrically it's a candidate "to the right of"
  // Remove — traversal picked it, focus left the overlay, and the
  // auto-dismiss above closed the confirm on a plain Right press.
  LogicalKeyboardKey get _nextKey => widget.compact
      ? LogicalKeyboardKey.arrowDown
      : LogicalKeyboardKey.arrowRight;
  LogicalKeyboardKey get _previousKey => widget.compact
      ? LogicalKeyboardKey.arrowUp
      : LogicalKeyboardKey.arrowLeft;

  KeyEventResult _onRemoveKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == _nextKey) {
      _cancelFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return event.logicalKey == _previousKey
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  KeyEventResult _onCancelKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == _previousKey) {
      _removeFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return event.logicalKey == _nextKey
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      Focus(
        canRequestFocus: false,
        onKeyEvent: _onRemoveKey,
        child: AppButton(
          onClick: _guardedConfirm,
          compact: true,
          focusNode: _removeFocus,
          child: const AppText('Remove'),
        ),
      ),
      SizedBox(width: 16.du(context), height: 8.du(context)),
      Focus(
        canRequestFocus: false,
        onKeyEvent: _onCancelKey,
        child: AppButton(
          onClick: _guardedCancel,
          compact: true,
          focusNode: _cancelFocus,
          child: const AppText('Cancel'),
        ),
      ),
    ];

    return Positioned.fill(
      child: Focus(
        canRequestFocus: false,
        onFocusChange: _handleRegionFocusChange,
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _trapEscape,
          child: ColoredBox(
            color: AppScrims.dialog.withValues(alpha: 0.85),
            child: Center(
              child: Padding(
                padding: widget.compact
                    ? EdgeInsets.symmetric(horizontal: 8.du(context))
                    : EdgeInsets.zero,
                // A Column would hard-overflow content too big for a small
                // card's overlay (seen on the narrow
                // ContinueWatchingPoster card), so scale the whole block
                // down to fit.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (widget.compact ? 140 : 260).du(context),
                        ),
                        child: AppText(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: AppTypography.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: 8.du(context)),
                      if (widget.compact)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [buttons[0], buttons[1], buttons[2]],
                        )
                      else
                        Row(mainAxisSize: MainAxisSize.min, children: buttons),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
