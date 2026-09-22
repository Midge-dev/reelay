import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'watch_together_row.dart' show MergedRoom;

const _barHeight = 68.0;

/// Ports the "Watch Together bar" from the Nocturne redesign — a single
/// fixed slot that never multiplies, replacing the old full row of
/// [MergedRoom] cards on Home. One room and five rooms produce the same
/// silhouette; extra rooms collapse into a trailing "N more rooms" segment.
/// See DESIGN.md's Watch Together section and the design handoff's
/// "WATCH TOGETHER · MORE THAN ONE ROOM" note.
///
/// Which room gets the bar: one you already have a seat in (hosting counts
/// — the host holds seat 0), otherwise the first live room. The real
/// tie-break for "otherwise, hosted by someone you've watched with before,
/// else most recently started" needs data this app doesn't track yet
/// (watch-history-with and room start time), so it's simplified to "first
/// live room" until that data exists — see RoomCard/the future rooms panel
/// (screen 12) for the full per-room detail this bar deliberately omits.
class WatchTogetherBar extends StatefulWidget {
  final List<MergedRoom> rooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final Future<bool> Function(MergedRoom) onEndSession;
  final ValueChanged<MergedRoom> onSelectRoom;
  final FocusNode? focusNode;
  final bool autofocus;

  const WatchTogetherBar({
    super.key,
    required this.rooms,
    this.myRoomId,
    this.hostedRoomIds = const {},
    required this.onEndSession,
    required this.onSelectRoom,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<WatchTogetherBar> createState() => _WatchTogetherBarState();
}

class _WatchTogetherBarState extends State<WatchTogetherBar> {
  bool _confirmingEnd = false;
  bool _endFailed = false;
  Object? _endResetToken;

  MergedRoom _selectRoom() {
    for (final merged in widget.rooms) {
      final id = merged.room.roomId;
      if (id == widget.myRoomId || widget.hostedRoomIds.contains(id))
        return merged;
    }
    return widget.rooms.first;
  }

  void _openEndConfirm() => setState(() => _confirmingEnd = true);
  void _closeEndConfirm() => setState(() => _confirmingEnd = false);

  Future<void> _endNow(MergedRoom merged) async {
    setState(() => _confirmingEnd = false);
    final token = Object();
    _endResetToken = token;
    final ok = await widget.onEndSession(merged);
    if (!mounted || _endResetToken != token) return;
    if (!ok) {
      setState(() => _endFailed = true);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _endResetToken == token)
          setState(() => _endFailed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rooms.isEmpty) return const SizedBox.shrink();

    final selected = _selectRoom();
    final room = selected.room;
    final isHosting = widget.hostedRoomIds.contains(room.roomId);
    final isSeated = isHosting || room.roomId == widget.myRoomId;
    final nobodyJoined = isHosting && room.occupants <= 1;
    final moreCount = widget.rooms.length - 1;

    final Color spineColor;
    final String headline;
    String? subline;
    if (isHosting) {
      spineColor = nobodyJoined ? AppColors.warning : AppColors.accent;
      headline = nobodyJoined
          ? 'Your room is open · nobody has joined'
          : 'Your room is open';
      subline = '${room.occupants} of ${room.maxSeats} watching';
    } else if (isSeated) {
      spineColor = AppColors.accent;
      headline = "You're in ${room.hostName}'s room";
      subline = '${room.occupants} of ${room.maxSeats} watching';
    } else {
      spineColor = AppColors.success;
      headline = "${room.hostName}'s room is live";
      subline = '${room.occupants} of ${room.maxSeats} seats · ${room.title}';
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: _barHeight.du(context),
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
          decoration: BoxDecoration(
            color: isSeated ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
            border: Border.all(
              color: isSeated ? AppColors.accent : AppColors.line,
              width: (isSeated ? AppShape.borderWidth : 1).du(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: AppShape.spineWidth.du(context),
                height: 32.du(context),
                decoration: BoxDecoration(
                  color: spineColor,
                  borderRadius: BorderRadius.circular(3.du(context)),
                ),
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              AppText(
                headline,
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: AppSpacing.md.du(context)),
              Flexible(
                child: AppText(
                  subline,
                  color: AppColors.ink3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
              if (isHosting && _endFailed)
                AppText("Can't reach relay", color: AppColors.ink3)
              else if (isHosting) ...[
                AppOutlinedButton(
                  compact: true,
                  onClick: () => widget.onSelectRoom(selected),
                  focusNode: widget.focusNode,
                  autofocus: widget.autofocus,
                  child: const AppText('Go back in'),
                ),
                SizedBox(width: AppSpacing.md.du(context)),
                Container(width: 1.du(context), height: 24.du(context), color: AppColors.lineStrong),
                SizedBox(width: AppSpacing.md.du(context)),
                // Never the first focus target — a D-pad slip must not be
                // able to close a room full of people.
                AppOutlinedButton(
                  compact: true,
                  onClick: _openEndConfirm,
                  child: const AppText('End'),
                ),
              ] else
                AppOutlinedButton(
                  compact: true,
                  enabled: room.occupants < room.maxSeats || isSeated,
                  onClick: () => widget.onSelectRoom(selected),
                  focusNode: widget.focusNode,
                  autofocus: widget.autofocus,
                  child: AppText(
                    isSeated
                        ? 'Go back in'
                        : (room.occupants >= room.maxSeats ? 'Full' : 'Join'),
                  ),
                ),
              if (moreCount > 0) ...[
                SizedBox(width: AppSpacing.md.du(context)),
                Container(width: 1.du(context), height: 24.du(context), color: AppColors.lineStrong),
                SizedBox(width: AppSpacing.md.du(context)),
                AppText(
                  '$moreCount more room${moreCount == 1 ? '' : 's'}',
                  color: AppColors.accent300,
                ),
              ],
            ],
          ),
        ),
        if (_confirmingEnd)
          _EndSessionConfirm(
            onKeepOpen: _closeEndConfirm,
            onEndForEveryone: () => _endNow(selected),
          ),
      ],
    );
  }
}

/// The dialog behind ending a hosted session — the one confirm dialog
/// Watch Together uses (DESIGN.md #12: destructive-but-reversible acts
/// don't get one, but ending a room affects other people, so it does).
/// Focus defaults to "Keep it open"; the destructive option is never the
/// default and carries the error spine.
class _EndSessionConfirm extends StatelessWidget {
  final VoidCallback onKeepOpen;
  final VoidCallback onEndForEveryone;

  const _EndSessionConfirm({
    required this.onKeepOpen,
    required this.onEndForEveryone,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppScrims.dialog,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520.du(context)),
            child: Container(
              padding: EdgeInsets.all(AppSpacing.xxl.du(context)),
              decoration: BoxDecoration(
                color: AppColors.surfaceOverlay,
                borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
                border: Border.all(color: AppColors.lineStrong),
                boxShadow: AppElevation.overlay,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText('End the session?', style: AppTypography.title2),
                  SizedBox(height: AppSpacing.md.du(context)),
                  AppText(
                    'Everyone will be dropped back to their own home screens. Your place is kept, and you can keep watching on your own.',
                    color: AppColors.ink2,
                  ),
                  SizedBox(height: AppSpacing.xl.du(context)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        onClick: onKeepOpen,
                        autofocus: true,
                        child: const AppText('Keep it open'),
                      ),
                      SizedBox(width: AppSpacing.md.du(context)),
                      AppOutlinedButton(
                        onClick: onEndForEveryone,
                        child: const AppText(
                          'End for everyone',
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
