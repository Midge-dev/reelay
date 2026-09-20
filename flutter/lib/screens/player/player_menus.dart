import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/list_item.dart';
import '../../kit/radio_button.dart';
import '../../kit/text.dart';
import '../../playback/playback_decision.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _menuWidth = 360.0;
const _menuMaxHeight = 480.0;

KeyEventResult _trapEdges(int index, int lastIndex, KeyEvent event) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
  if (key == LogicalKeyboardKey.arrowUp && index == 0) return KeyEventResult.handled;
  if (key == LogicalKeyboardKey.arrowDown && index == lastIndex) return KeyEventResult.handled;
  return KeyEventResult.ignored;
}

/// Ports PlayerScreen.kt's `SubtitleMenu` — every row's up/down/left/right
/// at the list edges is trapped (matches Kotlin's `FocusRequester.Cancel`
/// on every direction) rather than escaping to some other part of the
/// screen; only the back button (via [BackHandler]) dismisses it.
class SubtitleMenu extends StatelessWidget {
  final List<SubtitleOption> options;
  final int? selectedStreamId;
  final ValueChanged<SubtitleOption> onSelect;
  final VoidCallback onDismiss;

  const SubtitleMenu({
    super.key,
    required this.options,
    required this.selectedStreamId,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexWhere((o) => o.streamId == selectedStreamId).clamp(0, options.isEmpty ? 0 : options.length - 1);

    return BackHandler(
      onBack: onDismiss,
      child: Container(
        width: _menuWidth,
        constraints: const BoxConstraints(maxHeight: _menuMaxHeight),
        color: AppColors.scrim.withValues(alpha: 0.85),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText('Subtitles', style: AppTypography.titleMedium, color: AppColors.white),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected = option.streamId == selectedStreamId;
                  return Focus(
                    canRequestFocus: false,
                    onKeyEvent: (node, event) => _trapEdges(index, options.length - 1, event),
                    child: AppListItem(
                      selected: selected,
                      onClick: () => onSelect(option),
                      leading: AppRadioButton(selected: selected),
                      headline: AppText(option.label, color: AppColors.white),
                      autofocus: index == selectedIndex,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ports PlayerScreen.kt's `BitrateMenu` — same focus-trap shape as
/// [SubtitleMenu], listing [AppSettings.bitratePresets].
class BitrateMenu extends StatelessWidget {
  final int selectedKbps;
  final ValueChanged<int> onSelect;
  final VoidCallback onDismiss;

  const BitrateMenu({super.key, required this.selectedKbps, required this.onSelect, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final presets = AppSettings.bitratePresets;
    final selectedIndex = presets.indexWhere((p) => p.kbps == selectedKbps).clamp(0, presets.length - 1);

    return BackHandler(
      onBack: onDismiss,
      child: Container(
        width: 420,
        color: AppColors.scrim.withValues(alpha: 0.85),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText('Quality', style: AppTypography.titleMedium, color: AppColors.white),
            const SizedBox(height: 4),
            for (var index = 0; index < presets.length; index++) ...[
              if (index > 0) const SizedBox(height: 4),
              Builder(builder: (context) {
                final preset = presets[index];
                final selected = preset.kbps == selectedKbps;
                return Focus(
                  canRequestFocus: false,
                  onKeyEvent: (node, event) => _trapEdges(index, presets.length - 1, event),
                  child: AppListItem(
                    selected: selected,
                    onClick: () => onSelect(preset.kbps),
                    leading: AppRadioButton(selected: selected),
                    headline: AppText(preset.label, color: AppColors.white),
                    autofocus: index == selectedIndex,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
