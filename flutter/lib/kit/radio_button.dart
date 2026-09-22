import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

const _radioSize = 32.0;
const _radioDotSize = 16.0;

/// Ports ui/kit/RadioButton.kt — a bordered circle with an inner filled dot.
/// Purely decorative; used as a leading indicator inside a focusable row
/// (e.g. AppListItem) rather than being focusable itself.
class AppRadioButton extends StatelessWidget {
  final bool selected;

  const AppRadioButton({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _radioSize,
      height: _radioSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: selected ? AppColors.accent : AppColors.lineStrong, width: AppShape.borderWidth)),
      ),
      alignment: Alignment.center,
      child: selected
          ? const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent), child: SizedBox(width: _radioDotSize, height: _radioDotSize))
          : null,
    );
  }
}
