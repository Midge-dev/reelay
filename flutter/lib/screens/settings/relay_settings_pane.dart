import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/neon_scrollbar.dart';
import '../common/relay_status.dart';

const _dotGap = 20.0;

/// A (reachable, room-count) pair, or null while still probing — mirrors
/// Kotlin's `Pair<Boolean, Int>?`.
class RelayReachability {
  final bool reachable;
  final int roomCount;

  const RelayReachability(this.reachable, this.roomCount);
}

String relayStatusLabel(RelayReachability? status) {
  if (status == null) return '…';
  if (!status.reachable) return 'Not responding';
  return '${status.roomCount} room${status.roomCount == 1 ? '' : 's'}';
}

/// Ports ui/settings/SettingsScreen.kt's `RelaySettingsPane` — relay
/// list management (make default / edit / remove), pairing-from-phone,
/// and the one-shot "testing a newly added relay" status line.
class RelaySettingsPane extends StatelessWidget {
  final AppSettings settings;
  final Map<String, RelayReachability?> relayStatuses;
  final String? editingRelayId;
  final String? pairingUrl;
  final String? pairingError;
  final String? testingRelayName;
  final RelayStatus testStatus;
  final VoidCallback onBack;
  final ValueChanged<RelayEntry> onMakeDefault;
  final ValueChanged<RelayEntry> onEdit;
  final ValueChanged<RelayEntry> onRemove;
  final VoidCallback onAddRelay;
  final VoidCallback onCancelPairing;
  final FocusNode addRelayFocus;
  final FocusNode cancelPairingFocus;
  final FocusNode backFocus;

  const RelaySettingsPane({
    super.key,
    required this.settings,
    required this.relayStatuses,
    this.editingRelayId,
    this.pairingUrl,
    this.pairingError,
    this.testingRelayName,
    required this.testStatus,
    required this.onBack,
    required this.onMakeDefault,
    required this.onEdit,
    required this.onRemove,
    required this.onAddRelay,
    required this.onCancelPairing,
    required this.addRelayFocus,
    required this.cancelPairingFocus,
    required this.backFocus,
  });

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.all(48.du(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 24.du(context)),
                    // The kit's text action, so it gets the system's padding
                    // and focus treatment — the hand-rolled stadium had
                    // neither, and clipped its own chevron.
                    child: AppGhostButton(
                      onClick: onBack,
                      focusNode: backFocus,
                      dense: true,
                      child: const AppText('‹ Settings', color: null),
                    ),
                  ),
                  AppText('Relay settings', style: AppTypography.title1),
                  Padding(
                    padding: EdgeInsets.only(
                      top: 8.du(context),
                      bottom: 24.du(context),
                    ),
                    child: AppText(
                      'Anyone who keeps a relay running can be added by address — a cloud host, a Pi in '
                      "someone's front room, whatever answers.",
                      color: AppColors.ink3,
                    ),
                  ),
                  for (final entry in settings.relays)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.du(context)),
                      child: RelayRow(
                        entry: entry,
                        status: relayStatuses[entry.id],
                        onMakeDefault: () => onMakeDefault(entry),
                        onEdit: () => onEdit(entry),
                        onRemove: () => onRemove(entry),
                      ),
                    ),
                  AppOutlinedButton(
                    onClick: onAddRelay,
                    focusNode: addRelayFocus,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(PhosphorIconsRegular.plus, size: 22),
                        SizedBox(width: AppSpacing.md.du(context)),
                        const AppText('Add a relay', color: null),
                      ],
                    ),
                  ),
                  if (pairingError != null)
                    Padding(
                      padding: EdgeInsets.only(top: 16.du(context)),
                      child: AppText(pairingError!),
                    ),
                  if (pairingUrl != null)
                    Container(
                      margin: EdgeInsets.only(top: 12.du(context)),
                      padding: EdgeInsets.all(24.du(context)),
                      color: AppColors.surface,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 160.du(context),
                            height: 160.du(context),
                            color: AppColors.inkOnArt,
                            padding: EdgeInsets.all(12.du(context)),
                            child: QrImageView(
                              data: pairingUrl!,
                              backgroundColor: AppColors.inkOnArt,
                            ),
                          ),
                          SizedBox(width: 24.du(context)),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppText(
                                  'Scan with your phone (same Wi-Fi as the TV), or visit:',
                                ),
                                SizedBox(height: 12.du(context)),
                                AppText(pairingUrl!, style: AppTypography.body),
                                SizedBox(height: 12.du(context)),
                                AppText(
                                  editingRelayId != null
                                      ? "Update the nickname and URL there — it'll change here automatically."
                                      : "Type a nickname and the relay URL there — it'll appear here automatically.",
                                ),
                                SizedBox(height: 12.du(context)),
                                AppOutlinedButton(
                                  onClick: onCancelPairing,
                                  focusNode: cancelPairingFocus,
                                  child: const AppText('Cancel'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (testingRelayName != null)
                    Padding(
                      padding: EdgeInsets.only(top: 12.du(context)),
                      child: RelayStatusLine(
                        status: testStatus,
                        relayNickname: testingRelayName!,
                        onRetry: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: 48.du(context),
              horizontal: 12.du(context),
            ),
            child: NeonScrollbar(controller: scrollController),
          ),
        ],
      ),
    );
  }
}

class RelayRow extends StatelessWidget {
  final RelayEntry entry;
  final RelayReachability? status;
  final VoidCallback onMakeDefault;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const RelayRow({
    super.key,
    required this.entry,
    this.status,
    required this.onMakeDefault,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 2.du(context)),
        borderRadius: BorderRadius.circular(8.du(context)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 28.du(context),
        vertical: 20.du(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The dot belongs to the name line, not the whole row — on
                // the row it sat halfway down, below the name.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RelayStatusDot(
                      status: status?.reachable == true
                          ? RelayStatus.dotOnly
                          : RelayStatus.silent,
                    ),
                    SizedBox(width: _dotGap.du(context)),
                    AppText(entry.nickname),
                    if (entry.isDefault) ...[
                      SizedBox(width: 12.du(context)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.du(context),
                          vertical: 7.du(context),
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(50.du(context)),
                        ),
                        // A tight, evenly split line box: the body style's
                        // tall line height put its extra leading mostly
                        // above the word, so it sat off-centre in the pill.
                        child: AppText(
                          'Default',
                          style: AppTypography.caption.copyWith(
                            height: 1,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                          color: AppColors.inkOnArt,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 6.du(context)),
                Padding(
                  padding: EdgeInsets.only(left: (8 + _dotGap).du(context)),
                  child: AppText(
                    relayStatusLabel(status),
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!entry.isDefault) ...[
                AppOutlinedButton(
                  onClick: onMakeDefault,
                  child: const AppText('Make default'),
                ),
                SizedBox(width: 16.du(context)),
              ],
              AppOutlinedButton(onClick: onEdit, child: const AppText('Edit')),
              SizedBox(width: 16.du(context)),
              AppOutlinedButton(
                onClick: onRemove,
                child: const AppText('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
