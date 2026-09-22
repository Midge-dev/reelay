import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/filter_chip.dart';
import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/list_item.dart';
import '../../kit/radio_button.dart';
import '../../kit/switch.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Temporary manual-verification screen for the Phase 3 kit library —
/// not part of the real app shell. Wired in as AppRoot's Checking
/// placeholder purely so it's visible in the macOS fast loop while there
/// are no real screens yet; replace with the real splash/auth flow in
/// Phase 4.
class KitShowcaseScreen extends StatefulWidget {
  const KitShowcaseScreen({super.key});

  @override
  State<KitShowcaseScreen> createState() => _KitShowcaseScreenState();
}

class _KitShowcaseScreenState extends State<KitShowcaseScreen> {
  bool _switchOn = true;
  int _selectedChip = 0;
  int _selectedListItem = 0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppText('Reelay kit', style: AppTypography.title1),
              const SizedBox(height: AppSpacing.xs),
              const AppText('Phase 3 component showcase — D-pad through these', style: AppTypography.body),
              const SizedBox(height: AppSpacing.xxl),

              const AppText('Buttons', style: AppTypography.rowLabel),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppButton(onClick: () {}, child: const AppText('Play')),
                  const SizedBox(width: AppSpacing.md),
                  AppOutlinedButton(onClick: () {}, child: const AppText('Watch together')),
                  const SizedBox(width: AppSpacing.md),
                  AppIconButton(onClick: () {}, child: const AppIcon(_playIcon)),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              const AppText('Cards', style: AppTypography.rowLabel),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 180,
                child: Row(
                  children: List.generate(4, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      child: SizedBox(
                        width: 140,
                        child: AppCard(
                          onClick: () {},
                          onLongClick: () {},
                          child: CardContainer(
                            imageCard: Container(height: 120, color: AppColors.surface),
                            title: Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: AppText('Card ${i + 1}', style: AppTypography.label),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              const AppText('Filter chips', style: AppTypography.rowLabel),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: List.generate(3, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: AppFilterChip(
                      selected: _selectedChip == i,
                      onClick: () => setState(() => _selectedChip = i),
                      child: AppText('Option ${i + 1}'),
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.xxl),

              const AppText('List items', style: AppTypography.rowLabel),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: 280,
                child: Column(
                  children: List.generate(3, (i) {
                    return AppListItem(
                      selected: _selectedListItem == i,
                      onClick: () => setState(() => _selectedListItem = i),
                      leading: AppRadioButton(selected: _selectedListItem == i),
                      headline: AppText('Server ${i + 1}'),
                    );
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              const AppText('Switch', style: AppTypography.rowLabel),
              const SizedBox(height: AppSpacing.md),
              AppSwitch(checked: _switchOn, onCheckedChange: (v) => setState(() => _switchOn = v)),
            ],
          ),
        ),
      ),
    );
  }
}

// A tiny built-in glyph so this file doesn't need to import Icons just for
// one temporary showcase icon.
const _playIcon = IconData(0xe037, fontFamily: 'MaterialIcons');
