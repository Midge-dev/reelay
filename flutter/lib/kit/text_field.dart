import 'package:flutter/widgets.dart';

import '../screens/common/click_to_type_text_field.dart';
import '../theme/scale.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'text.dart';

/// A labelled field, typed with the TV's own keyboard: a box with its
/// micro label inside over the value, raised and outlined in the accent
/// when focused — setup's typed sign-in (O3b), and the add-profile dialog
/// (07b). The whole box is what takes focus, so an empty field with no hint
/// still shows where focus is.
class AppTextField extends StatefulWidget {
  /// The micro role: uppercase.
  final String label;
  final String value;
  final String? hint;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  /// The keyboard's Done, once focus is back on the field.
  final VoidCallback? onSubmitted;
  final bool enabled;
  final bool obscure;

  /// A short note right of the label ("✓ Loft"), in the success colour.
  final String? trailing;

  const AppTextField({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.focusNode,
    required this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.obscure = false,
    this.trailing,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 22.du(context),
        vertical: AppSpacing.md.du(context),
      ),
      decoration: BoxDecoration(
        color: _focused ? AppColors.surfaceRaised : AppColors.surface,
        border: Border.all(
          color: _focused ? AppColors.accent : AppColors.line,
          width: AppShape.borderWidth.du(context),
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: AppText(widget.label, style: AppTypography.micro)),
              if (widget.trailing case final trailing?)
                AppText(trailing, style: AppTypography.caption, color: AppColors.success),
            ],
          ),
          SizedBox(height: AppSpacing.xs.du(context)),
          ClickToTypeTextField(
            value: widget.value,
            onValueChange: widget.onChanged,
            focusNode: widget.focusNode,
            hintText: widget.hint,
            showBorder: false,
            obscureText: widget.obscure,
            onSubmitted: widget.onSubmitted,
            expand: true,
            onFocusChange: (f) => setState(() => _focused = f),
            textStyle: AppTypography.body.copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
    // Disabled: 45% and out of the focus order (DESIGN.md).
    if (!widget.enabled) {
      return Opacity(opacity: 0.45, child: ExcludeFocus(child: field));
    }
    return field;
  }
}
