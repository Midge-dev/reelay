import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ServerReachability;
import '../../focus/back_handler.dart';
import '../../kit/card.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _dialogWidth = 900.0;
const _rowMinHeight = 88.0;

/// Ports screen 03d — "Where to watch from". Duplicates fold into one card
/// everywhere except here: this is the one moment the choice surfaces,
/// exactly at the point it matters (DESIGN.md non-negotiable #10). Rows are
/// already in fold priority order (local before relayed before
/// unreachable — see [FoldedWork.copies]), so the first row is always
/// what's currently playing.
///
/// The mockup's rows also state direct-play-vs-transcode cost, which needs
/// a per-copy detail fetch this dialog doesn't have (only the active
/// copy's [PlexMovieDetail] is ever loaded) — showing a real distance
/// (local/relayed/unreachable) and omitting an invented cost figure is the
/// honest simplification, matching DESIGN.md's "real data, no invented
/// curation".
class SourcePickerDialog extends StatelessWidget {
  final String title;
  final FoldedWork<PlexLibraryItem> work;
  final Sourced<PlexLibraryItem> activeCopy;
  final ValueChanged<Sourced<PlexLibraryItem>> onSelect;
  final VoidCallback onClose;

  const SourcePickerDialog({
    super.key,
    required this.title,
    required this.work,
    required this.activeCopy,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final copies = work.copies;
    return Positioned.fill(
      child: ColoredBox(
        color: AppScrims.dialog,
        child: Center(
          child: BackHandler(
            onBack: onClose,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _dialogWidth.du(context),
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusLg.du(context),
                  ),
                  border: Border.all(color: AppColors.lineStrong),
                  boxShadow: AppElevation.overlay,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            PhosphorIconsRegular.hardDrives,
                            size: 26,
                            tint: AppColors.accent300,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText(
                            'WHERE TO WATCH FROM',
                            style: AppTypography.micro,
                            color: AppColors.accent300,
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.lg.du(context)),
                      AppText(
                        '$title is on ${copies.length} of your servers',
                        style: AppTypography.title2,
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (index, copy) in copies.indexed) ...[
                            if (index > 0)
                              SizedBox(height: AppSpacing.md.du(context)),
                            _SourceRow(
                              copy: copy,
                              isActive:
                                  copy.server.machineIdentifier ==
                                  activeCopy.server.machineIdentifier,
                              autofocus: index == 0,
                              onClick: () {
                                onSelect(copy);
                                onClose();
                              },
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: AppSpacing.lg.du(context)),
                      AppText(
                        'Back closes and keeps the current source',
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final Sourced<PlexLibraryItem> copy;
  final bool isActive;
  final bool autofocus;
  final VoidCallback onClick;

  const _SourceRow({
    required this.copy,
    required this.isActive,
    required this.autofocus,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final unreachable = copy.reachability == ServerReachability.unreachable;
    final (statusColor, statusLabel) = isActive
        ? (AppColors.success, 'Chosen')
        : switch (copy.reachability) {
            ServerReachability.local => (AppColors.success, 'Local'),
            ServerReachability.relayed => (AppColors.warning, 'Relayed'),
            ServerReachability.unreachable => (AppColors.error, 'Unreachable'),
          };

    return Opacity(
      opacity: unreachable ? 0.45 : 1,
      child: AppCard(
        onClick: onClick,
        enabled: !unreachable && !isActive,
        selected: isActive,
        autofocus: autofocus,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowMinHeight.du(context)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl.du(context),
              vertical: AppSpacing.md.du(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(copy.server.name, style: AppTypography.label),
                      SizedBox(height: 3.du(context)),
                      AppText(
                        'Plex · ${copy.reachability.name}',
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.lg.du(context)),
                AppText(
                  statusLabel,
                  style: AppTypography.caption,
                  color: statusColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
