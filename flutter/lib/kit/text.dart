import 'package:flutter/widgets.dart';

import '../theme/typography.dart';
import 'content_color.dart';

/// Ports ui/kit/Text.kt — resolves color against the ambient ContentColor
/// unless one is passed explicitly.
class AppText extends StatelessWidget {
  final String text;
  final Color? color;
  // Nullable rather than defaulting to AppTypography.body directly — see
  // AppCard.border's matching comment (AppTypography's roles are also
  // theme-derived now, via AppColors, so they're no longer compile-time
  // constants either).
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const AppText(
    this.text, {
    super.key,
    this.color,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? ContentColor.of(context);
    return Text(
      text,
      style: (style ?? AppTypography.body).copyWith(color: resolvedColor),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
