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
import '../../theme/scale.dart';
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
        padding: EdgeInsets.all(AppSpacing.xxl.du(context)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText('Reelay kit', style: AppTypography.title1),
              SizedBox(height: AppSpacing.xs.du(context)),
              AppText(
                'Phase 3 component showcase — D-pad through these',
                style: AppTypography.body,
              ),
              SizedBox(height: AppSpacing.xxl.du(context)),

              AppText('Buttons', style: AppTypography.rowLabel),
              SizedBox(height: AppSpacing.md.du(context)),
              Row(
                children: [
                  AppButton(onClick: () {}, child: const AppText('Play')),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppOutlinedButton(
                    onClick: () {},
                    child: const AppText('Watch together'),
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppIconButton(
                    onClick: () {},
                    child: const AppIcon(_playIcon),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xxl.du(context)),

              AppText('Cards', style: AppTypography.rowLabel),
              SizedBox(height: AppSpacing.md.du(context)),
              SizedBox(
                height: 180.du(context),
                child: Row(
                  children: List.generate(4, (i) {
                    return Padding(
                      padding: EdgeInsets.only(
                        right: AppSpacing.lg.du(context),
                      ),
                      child: SizedBox(
                        width: 140.du(context),
                        child: AppCard(
                          onClick: () {},
                          onLongClick: () {},
                          child: CardContainer(
                            imageCard: Container(
                              height: 120.du(context),
                              color: AppColors.surface,
                            ),
                            title: Padding(
                              padding: EdgeInsets.only(
                                top: AppSpacing.xs.du(context),
                              ),
                              child: AppText(
                                'Card ${i + 1}',
                                style: AppTypography.label,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(height: AppSpacing.xxl.du(context)),

              AppText('Filter chips', style: AppTypography.rowLabel),
              SizedBox(height: AppSpacing.md.du(context)),
              Row(
                children: List.generate(3, (i) {
                  return Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm.du(context)),
                    child: AppFilterChip(
                      selected: _selectedChip == i,
                      onClick: () => setState(() => _selectedChip = i),
                      child: AppText('Option ${i + 1}'),
                    ),
                  );
                }),
              ),
              SizedBox(height: AppSpacing.xxl.du(context)),

              AppText('List items', style: AppTypography.rowLabel),
              SizedBox(height: AppSpacing.md.du(context)),
              SizedBox(
                width: 280.du(context),
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
              SizedBox(height: AppSpacing.xxl.du(context)),

              AppText('Switch', style: AppTypography.rowLabel),
              SizedBox(height: AppSpacing.md.du(context)),
              AppSwitch(
                checked: _switchOn,
                onCheckedChange: (v) => setState(() => _switchOn = v),
              ),
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
