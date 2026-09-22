import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';

const _tileShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));
final _tileColors = SurfaceColors(container: AppColors.background, content: AppColors.ink3);
const _tileBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// Ports ui/settings/SettingsScreen.kt's `ChatCornerPicker` + `ChatCornerTile`
/// — a 2x2 grid mimicking a screen with two "chat bubble" bars stacked in
/// the corresponding corner.
class ChatCornerPicker extends StatelessWidget {
  final ChatOverlayCorner selected;
  final ValueChanged<ChatOverlayCorner> onSelect;

  const ChatCornerPicker({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ChatCornerTile(
                corner: ChatOverlayCorner.topStart,
                label: 'Top left',
                selected: selected == ChatOverlayCorner.topStart,
                onClick: () => onSelect(ChatOverlayCorner.topStart),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChatCornerTile(
                corner: ChatOverlayCorner.topEnd,
                label: 'Top right',
                selected: selected == ChatOverlayCorner.topEnd,
                onClick: () => onSelect(ChatOverlayCorner.topEnd),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ChatCornerTile(
                corner: ChatOverlayCorner.bottomStart,
                label: 'Bottom left',
                selected: selected == ChatOverlayCorner.bottomStart,
                onClick: () => onSelect(ChatOverlayCorner.bottomStart),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChatCornerTile(
                corner: ChatOverlayCorner.bottomEnd,
                label: 'Bottom right',
                selected: selected == ChatOverlayCorner.bottomEnd,
                onClick: () => onSelect(ChatOverlayCorner.bottomEnd),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatCornerTile extends StatelessWidget {
  final ChatOverlayCorner corner;
  final String label;
  final bool selected;
  final VoidCallback onClick;

  const _ChatCornerTile({required this.corner, required this.label, required this.selected, required this.onClick});

  @override
  Widget build(BuildContext context) {
    final stacksDownward = corner == ChatOverlayCorner.topStart || corner == ChatOverlayCorner.topEnd;
    final stackAlignment = switch (corner) {
      ChatOverlayCorner.topStart => AlignmentDirectional.topStart,
      ChatOverlayCorner.topEnd => AlignmentDirectional.topEnd,
      ChatOverlayCorner.bottomStart => AlignmentDirectional.bottomStart,
      ChatOverlayCorner.bottomEnd => AlignmentDirectional.bottomEnd,
    };
    final labelAlignment = switch (corner) {
      ChatOverlayCorner.topStart => AlignmentDirectional.bottomEnd,
      ChatOverlayCorner.topEnd => AlignmentDirectional.bottomStart,
      ChatOverlayCorner.bottomStart => AlignmentDirectional.topEnd,
      ChatOverlayCorner.bottomEnd => AlignmentDirectional.topStart,
    };
    final brightBar = selected ? AppColors.ink : AppColors.ink3;
    final dimBar = brightBar.withValues(alpha: selected ? 0.5 : 0.45);
    final labelColor = selected ? AppColors.accent : AppColors.ink3;

    final bars = [
      Container(width: 44, height: 8, decoration: BoxDecoration(color: brightBar, borderRadius: BorderRadius.circular(2))),
      Container(width: 30, height: 8, decoration: BoxDecoration(color: dimBar, borderRadius: BorderRadius.circular(2))),
    ];
    final ordered = stacksDownward ? bars : bars.reversed.toList();

    return SizedBox(
      height: 64,
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        shape: _tileShape,
        colors: _tileColors,
        border: _tileBorder,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              Align(
                alignment: stackAlignment,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [ordered[0], const SizedBox(height: 4), ordered[1]],
                ),
              ),
              Align(
                alignment: labelAlignment,
                child: AppText(
                  selected ? '$label ✓' : label,
                  color: labelColor,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11, height: 13 / 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
