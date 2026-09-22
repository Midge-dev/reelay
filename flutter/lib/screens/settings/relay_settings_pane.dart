import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/neon_scrollbar.dart';
import '../common/relay_status.dart';

const _rowShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
);
final _rowColors = SurfaceColors(
  container: AppColors.background,
  content: AppColors.ink3,
  focusedContent: AppColors.inkOnArt,
);
final _rowBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

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
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: FocusableSurface(
                      onClick: onBack,
                      focusNode: backFocus,
                      shape: const StadiumBorder(),
                      colors: SurfaceColors(
                        container: AppColors.transparent,
                        content: AppColors.ink3,
                      ),
                      child: AppText('‹ Settings', color: AppColors.ink3),
                    ),
                  ),
                  AppText('Relay settings', style: AppTypography.title1),
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 24),
                    child: AppText(
                      'Anyone who keeps a relay running can be added by address — a cloud host, a Pi in '
                      "someone's front room, whatever answers.",
                      color: AppColors.ink3,
                    ),
                  ),
                  for (final entry in settings.relays)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RelayRow(
                        entry: entry,
                        status: relayStatuses[entry.id],
                        onMakeDefault: () => onMakeDefault(entry),
                        onEdit: () => onEdit(entry),
                        onRemove: () => onRemove(entry),
                      ),
                    ),
                  SizedBox(
                    height: 64,
                    child: FocusableSurface(
                      onClick: onAddRelay,
                      focusNode: addRelayFocus,
                      shape: _rowShape,
                      colors: _rowColors,
                      border: _rowBorder,
                      child: const AppText('Add a relay'),
                    ),
                  ),
                  if (pairingError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: AppText(pairingError!),
                    ),
                  if (pairingUrl != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(24),
                      color: AppColors.surface,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 160,
                            height: 160,
                            color: AppColors.inkOnArt,
                            padding: const EdgeInsets.all(12),
                            child: QrImageView(
                              data: pairingUrl!,
                              backgroundColor: AppColors.inkOnArt,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppText(
                                  'Scan with your phone (same Wi-Fi as the TV), or visit:',
                                ),
                                const SizedBox(height: 12),
                                AppText(pairingUrl!, style: AppTypography.body),
                                const SizedBox(height: 12),
                                AppText(
                                  editingRelayId != null
                                      ? "Update the nickname and URL there — it'll change here automatically."
                                      : "Type a nickname and the relay URL there — it'll appear here automatically.",
                                ),
                                const SizedBox(height: 12),
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
                      padding: const EdgeInsets.only(top: 12),
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
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
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
        border: Border.all(color: AppColors.line, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RelayStatusDot(
            status: status?.reachable == true
                ? RelayStatus.dotOnly
                : RelayStatus.silent,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppText(entry.nickname),
                    if (entry.isDefault) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: AppText('Default', color: AppColors.inkOnArt),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                AppText(relayStatusLabel(status), color: AppColors.ink3),
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
                const SizedBox(width: 16),
              ],
              AppOutlinedButton(onClick: onEdit, child: const AppText('Edit')),
              const SizedBox(width: 16),
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
