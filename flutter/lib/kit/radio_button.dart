import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Ports ui/kit/RadioButton.kt — a bordered circle with an inner filled dot.
class AppRadioButton extends StatelessWidget {
  final bool selected;

  const AppRadioButton({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.white, width: 2))),
      alignment: Alignment.center,
      child: selected
          ? Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent))
          : null,
    );
  }
}
