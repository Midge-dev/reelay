import 'package:flutter/widgets.dart';

import '../theme/scale.dart';
import '../theme/typography.dart';
import 'content_color.dart';

/// Text in the app's type roles. Colour resolves: an explicit [color]; else the
/// ambient ContentColor when inside a surface (so a focused row's label
/// follows its focus state); else the type role's own colour (caption is
/// ink3, micro is accent, body is ink2 — typography.dart); else ink.
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
    final base = style ?? AppTypography.body;
    final resolvedColor = color ?? ContentColor.maybeOf(context) ?? base.color ?? ContentColor.of(context);
    return Text(
      text,
      style: base.copyWith(
        color: resolvedColor,
        fontSize: base.fontSize?.du(context),
        letterSpacing: base.letterSpacing?.du(context),
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
