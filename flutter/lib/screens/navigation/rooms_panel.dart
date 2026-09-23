import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart' show RelayEntry;
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../sync/relay_protocol.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../home/watch_together_row.dart' show MergedRoom;

const _panelWidth = 960.0;
const _railWidth = 80.0;
const _roomRowMinHeight = 110.0;
const _thumbWidth = 130.0;
const _thumbHeight = 74.0;
const _seatDot = 14.0;
const _maxSeatDots = 8;

/// Screen 12 — the rooms panel. Opens from the rail's Watch Together item
/// and from the Home bar's "N more rooms ›", over whatever screen is
/// showing (a panel, not a page). Grouped by relay, because a relay's
/// health is the reason a room is or is not joinable: an unreachable relay
/// keeps its group and explains itself rather than silently vanishing.
/// Back closes it and returns focus to wherever it came from.
class RoomsPanel extends StatefulWidget {
  final List<RelayEntry> relays;
  final Map<String, RelayHealth> relayHealth;
  final List<MergedRoom> rooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final ValueChanged<MergedRoom> onJoin;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const RoomsPanel({
    super.key,
    required this.relays,
    required this.relayHealth,
    required this.rooms,
    this.myRoomId,
    this.hostedRoomIds = const {},
    required this.onJoin,
    required this.onRetry,
    required this.onClose,
  });

  @override
  State<RoomsPanel> createState() => _RoomsPanelState();
}

class _RoomsPanelState extends State<RoomsPanel> {
  final _scope = FocusScopeNode(debugLabel: 'rooms-panel');

  @override
  void initState() {
    super.initState();
    // Claim focus on entry (DESIGN.md focus rules) — the first focusable
    // in reading order, whichever row or button that turns out to be.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scope.requestFocus();
      final first = _scope.traversalDescendants
          .where((n) => n.canRequestFocus)
          .firstOrNull;
      first?.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  String _headline(int count) => switch (count) {
    0 => 'No rooms are live',
    1 => 'One room is live',
    2 => 'Two rooms are live',
    3 => 'Three rooms are live',
    _ => '$count rooms are live',
  };

  // Up/down stay inside the panel: the panel is its own FocusScope, so
  // directional traversal never finds the rail behind it; left is
  // swallowed too so the rail can't be reached while it's open. Back is
  // the way out.
  KeyEventResult _trapLeft(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      node.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final byRelay = <String, List<MergedRoom>>{};
    for (final r in widget.rooms) {
      (byRelay[r.relay.id] ??= []).add(r);
    }
    // A reachable relay with nothing live adds a header over nothing — skip
    // it. An unreachable one always shows, since it explains missing rooms.
    final groups = [
      for (final relay in widget.relays)
        if ((byRelay[relay.id]?.isNotEmpty ?? false) ||
            widget.relayHealth[relay.id]?.isReachable == false)
          relay,
    ];

    return Stack(
      children: [
        Positioned.fill(
          left: _railWidth.du(context),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: ColoredBox(color: AppScrims.dialog),
          ),
        ),
        Positioned(
          left: _railWidth.du(context),
          top: 0,
          bottom: 0,
          width: _panelWidth.du(context),
          child: BackHandler(
            onBack: widget.onClose,
            child: FocusScope(
              node: _scope,
              onKeyEvent: _trapLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border(right: BorderSide(color: AppColors.line)),
                  boxShadow: AppElevation.overlay,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxxl.du(context),
                    vertical: 56.du(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText('WATCH TOGETHER', style: AppTypography.micro),
                      SizedBox(height: AppSpacing.sm.du(context)),
                      AppText(
                        _headline(widget.rooms.length),
                        style: AppTypography.title2,
                      ),
                      SizedBox(height: AppSpacing.xxl.du(context)),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final relay in groups) ...[
                                _RelayGroup(
                                  relay: relay,
                                  health: widget.relayHealth[relay.id],
                                  rooms: byRelay[relay.id] ?? const [],
                                  myRoomId: widget.myRoomId,
                                  hostedRoomIds: widget.hostedRoomIds,
                                  onJoin: widget.onJoin,
                                  onRetry: widget.onRetry,
                                ),
                                SizedBox(height: AppSpacing.xxl.du(context)),
                              ],
                              if (groups.isEmpty)
                                AppText(
                                  'Nobody is hosting right now. Start a room from any title’s Watch Together button.',
                                  style: AppTypography.body,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Container(height: 1.du(context), color: AppColors.line),
                      SizedBox(height: 26.du(context)),
                      AppText(
                        'Rooms appear here within a second of being opened. Back returns you to where you were.',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelayGroup extends StatelessWidget {
  final RelayEntry relay;
  final RelayHealth? health;
  final List<MergedRoom> rooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final ValueChanged<MergedRoom> onJoin;
  final VoidCallback onRetry;

  const _RelayGroup({
    required this.relay,
    required this.health,
    required this.rooms,
    required this.myRoomId,
    required this.hostedRoomIds,
    required this.onJoin,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final down = health?.isReachable == false;
    final statusColor = down ? AppColors.error : AppColors.success;
    final name = relay.nickname.isNotEmpty ? relay.nickname : 'Relay';
    final detail = down
        ? 'UNREACHABLE'
        : (health?.latencyMs != null ? '${health!.latencyMs} MS' : null);
    final label = [name.toUpperCase(), ?detail].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: AppSpacing.sm.du(context),
              height: AppSpacing.sm.du(context),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: AppSpacing.md.du(context)),
            AppText(
              label,
              style: AppTypography.micro,
              color: down ? AppColors.error : AppColors.ink3,
            ),
            SizedBox(width: AppSpacing.md.du(context)),
            Expanded(
              child: Container(height: 1.du(context), color: AppColors.line),
            ),
          ],
        ),
        SizedBox(height: 14.du(context)),
        if (down)
          _UnreachableRow(
            lastAnsweredAt: health?.lastAnsweredAt,
            onRetry: onRetry,
          )
        else
          for (final (i, merged) in rooms.indexed) ...[
            if (i > 0) SizedBox(height: 14.du(context)),
            _RoomRow(
              merged: merged,
              seated:
                  merged.room.roomId == myRoomId ||
                  hostedRoomIds.contains(merged.room.roomId),
              onJoin: () => onJoin(merged),
            ),
          ],
      ],
    );
  }
}

SurfaceColors get _roomRowColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _roomRowBorder =>
    SurfaceBorder(idle: SurfaceBorderSide.solid(AppColors.line));

/// One room: thumbnail, "Maya's room", title line, drawn seats (empty seats
/// are dashed, not implied — screen 10's rule), and the Join affordance.
/// The whole row is the focus target (focus rests on a leaf, and a row
/// with a single action has one leaf); the "Join" label inside it is the
/// visual of that action.
class _RoomRow extends StatefulWidget {
  final MergedRoom merged;
  final bool seated;
  final VoidCallback onJoin;

  const _RoomRow({
    required this.merged,
    required this.seated,
    required this.onJoin,
  });

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.merged.room;
    final full = room.occupants >= room.maxSeats && !widget.seated;
    final action = widget.seated ? 'Go back in' : (full ? 'Full' : 'Join');
    final shownSeats = room.maxSeats.clamp(0, _maxSeatDots);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _roomRowMinHeight.du(context)),
      child: FocusableSurface(
        onClick: full ? () {} : widget.onJoin,
        onFocusChange: (f) => setState(() => _focused = f),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        colors: _roomRowColors,
        border: _roomRowBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl.du(context),
            vertical: 18.du(context),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  AppShape.radiusSm.du(context),
                ),
                child: SizedBox(
                  width: _thumbWidth.du(context),
                  height: _thumbHeight.du(context),
                  child: ColoredBox(color: AppColors.surfaceOverlay),
                ),
              ),
              SizedBox(width: 22.du(context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppText(
                      "${room.hostName}'s room",
                      style: AppTypography.body.copyWith(
                        height: 1.3,
                        fontWeight: _focused
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                      color: _focused ? AppColors.ink : AppColors.ink2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppSpacing.xs.du(context)),
                    AppText(
                      room.title,
                      style: AppTypography.caption,
                      color: _focused ? AppColors.ink2 : AppColors.ink3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 22.du(context)),
              for (var i = 0; i < shownSeats; i++) ...[
                if (i > 0) SizedBox(width: AppSpacing.sm.du(context)),
                _Seat(filled: i < room.occupants, active: _focused),
              ],
              SizedBox(width: AppSpacing.lg.du(context)),
              AppText(
                '${room.occupants} of ${room.maxSeats}',
                style: AppTypography.caption,
                color: _focused ? AppColors.ink2 : AppColors.ink3,
              ),
              SizedBox(width: 22.du(context)),
              Container(
                height: 52.du(context),
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl.du(context),
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusMd.du(context),
                  ),
                  border: Border.all(
                    color: _focused ? AppColors.accent : AppColors.lineStrong,
                    width: AppShape.borderWidth.du(context),
                  ),
                ),
                child: AppText(
                  action,
                  style: AppTypography.caption.copyWith(
                    fontWeight: _focused ? FontWeight.w500 : FontWeight.w400,
                  ),
                  color: _focused ? AppColors.ink : AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  final bool filled;
  final bool active;

  const _Seat({required this.filled, required this.active});

  @override
  Widget build(BuildContext context) {
    final size = _seatDot.du(context);
    if (filled) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.accent300 : AppColors.ink4,
        ),
      );
    }
    // Empty seats are drawn, not implied.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.ink4,
          width: AppShape.borderWidth.du(context),
        ),
      ),
    );
  }
}

class _UnreachableRow extends StatelessWidget {
  final DateTime? lastAnsweredAt;
  final VoidCallback onRetry;

  const _UnreachableRow({required this.lastAnsweredAt, required this.onRetry});

  String _since(BuildContext context) {
    final at = lastAnsweredAt;
    if (at == null) return 'No answer yet · retrying every 5 seconds';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return 'No answer since $hh:$mm · retrying every 5 seconds';
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: LeadingSpinePainter(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        color: AppColors.error,
        width: AppSpacing.xs.du(context),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xl.du(context),
          vertical: 22.du(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
          border: Border.all(color: AppColors.line, width: 1.du(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(_since(context), color: AppColors.ink2),
                  SizedBox(height: AppSpacing.xs.du(context)),
                  AppText(
                    'Rooms hosted here cannot be joined until it comes back.',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            SizedBox(width: 20.du(context)),
            AppOutlinedButton(
              compact: true,
              onClick: onRetry,
              child: const AppText('Retry now'),
            ),
          ],
        ),
      ),
    );
  }
}
