import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/settings/app_settings.dart';
import '../../focus/row_end_stop.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/scroll_peek.dart';
import '../../kit/text.dart';
import '../../sync/relay_protocol.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

const _visibleRoomCards = 3;
const _roomCardSpring = SpringDescription(mass: 1, stiffness: 400, damping: 30);

/// One live room, merged with the relay entry that's hosting it.
class MergedRoom {
  final RelayEntry relay;
  final RelayRoomSummary room;

  const MergedRoom(this.relay, this.room);
}

/// Home's row of live Watch Together rooms.
class WatchTogetherRow extends StatelessWidget {
  final PlexServer server;
  final List<MergedRoom> rooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final Future<bool> Function(MergedRoom) onEndSession;
  final ValueChanged<MergedRoom> onSelectRoom;
  final bool firstCardAutofocus;
  final FocusNode rowAnchorFocusNode;
  final ScrollController scrollController;

  const WatchTogetherRow({
    super.key,
    required this.server,
    required this.rooms,
    this.myRoomId,
    this.hostedRoomIds = const {},
    required this.onEndSession,
    required this.onSelectRoom,
    this.firstCardAutofocus = false,
    required this.rowAnchorFocusNode,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();
    final relayCount = rooms.map((r) => r.relay.id).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 32.du(context),
            top: 32.du(context),
            bottom: 16.du(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.du(context),
                height: 8.du(context),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                ),
              ),
              SizedBox(width: 12.du(context)),
              AppText('Watch Together', style: AppTypography.rowLabel),
              SizedBox(width: 12.du(context)),
              AppText(
                '${rooms.length} room${rooms.length == 1 ? '' : 's'} live · $relayCount relay${relayCount == 1 ? '' : 's'}',
                color: AppColors.ink3,
              ),
            ],
          ),
        ),
        SizedBox(
          // Tall enough for RoomCard's real content height (image + two
          // text rows + button row + padding) — a horizontal ListView
          // needs a bounded cross-axis
          // height, so this picks one with headroom rather than the
          // arbitrary 260 that clipped the card. +12 further for
          // EdgeFadeRow's ShaderMask bounds — see the matching comment on
          // Continue Watching's SizedBox in home_screen.dart. Bumped for
          // Nocturne's larger type scale; this whole row is superseded by
          // the single-slot Watch Together bar in the redesign (see
          // DESIGN.md), so it isn't worth tuning further than "fits".
          height: 410.du(context),
          child: EdgeFadeRow(
            child: RowEndStop(
              child: ListView.separated(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                // See the matching comment on Home's rows — ListView clips its
                // children by default, and RoomCard has a focus-scale that
                // bleeds past its own bounds.
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(
                  horizontal: 48.du(context),
                  vertical: 10.du(context),
                ),
                itemCount:
                    rooms.length + (rooms.length > _visibleRoomCards ? 1 : 0),
                separatorBuilder: (context, index) =>
                    SizedBox(width: 20.du(context)),
                itemBuilder: (context, index) {
                  if (index >= rooms.length) {
                    return _OverflowTile(
                      count: rooms.length - _visibleRoomCards,
                      onClick: () => scrollController.animateTo(
                        (_visibleRoomCards * 320.0).du(context),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                      ),
                    );
                  }
                  final merged = rooms[index];
                  return RoomCard(
                    key: ValueKey('${merged.relay.id}:${merged.room.roomId}'),
                    server: server,
                    merged: merged,
                    isMine: merged.room.roomId == myRoomId,
                    isHosted: hostedRoomIds.contains(merged.room.roomId),
                    onClick: () => onSelectRoom(merged),
                    onEndSession: onEndSession,
                    joinFocusNode: index == 0 ? rowAnchorFocusNode : null,
                    autofocus: index == 0 && firstCardAutofocus,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

RoundedRectangleBorder _roomCardShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8.du(context))),
    );

/// Hand-rolls its own focus tracking
/// (not FocusableSurface) so it can layer the card's scale/border while
/// still hosting two independently-focusable buttons inside. Scrolls
/// itself into view on focus via Scrollable.ensureVisible — Flutter's
/// Scrollable doesn't auto-scroll on descendant focus.
class RoomCard extends StatefulWidget {
  final PlexServer server;
  final MergedRoom merged;
  final bool isMine;
  final bool isHosted;
  final VoidCallback onClick;
  final Future<bool> Function(MergedRoom) onEndSession;
  final FocusNode? joinFocusNode;
  final bool autofocus;

  const RoomCard({
    super.key,
    required this.server,
    required this.merged,
    required this.isMine,
    required this.isHosted,
    required this.onClick,
    required this.onEndSession,
    this.joinFocusNode,
    this.autofocus = false,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final FocusNode _joinFocusNode;
  bool _ownsJoinFocusNode = false;
  bool _cardFocused = false;
  bool _failed = false;
  Object? _failedResetToken;

  @override
  void initState() {
    super.initState();
    // Default upperBound is 1.0 — since the focused target below is 1.04,
    // an explicit bound is needed or the spring's target gets silently
    // clamped straight back to 1.0 (see the matching fix in kit/card.dart).
    _scaleController = AnimationController(
      value: 1,
      vsync: this,
      upperBound: 1.04,
    );
    _ownsJoinFocusNode = widget.joinFocusNode == null;
    _joinFocusNode =
        widget.joinFocusNode ?? FocusNode(debugLabel: 'room-card-join');
  }

  @override
  void dispose() {
    _scaleController.dispose();
    if (_ownsJoinFocusNode) _joinFocusNode.dispose();
    super.dispose();
  }

  void _handleCardFocusChange(bool hasFocus) {
    setState(() => _cardFocused = hasFocus);
    final target = hasFocus ? 1.04 : 1.0;
    _scaleController.animateWith(
      SpringSimulation(_roomCardSpring, _scaleController.value, target, 0),
    );
    if (hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCardVisible(context);
      });
    }
  }

  Future<void> _endNow() async {
    final token = Object();
    _failedResetToken = token;
    final ok = await widget.onEndSession(widget.merged);
    if (!mounted || _failedResetToken != token) return;
    if (!ok) {
      setState(() => _failed = true);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _failedResetToken == token)
          setState(() => _failed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.merged.room;
    final full = room.occupants >= room.maxSeats;
    final joinLabel = full ? 'Full' : (widget.isMine ? 'Rejoin' : 'Join');

    return Focus(
      canRequestFocus: false,
      onFocusChange: _handleCardFocusChange,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) =>
            Transform.scale(scale: _scaleController.value, child: child),
        child: Container(
          width: 300.du(context),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8.du(context)),
            border: _cardFocused
                ? Border.all(color: AppColors.accent, width: 2.du(context))
                : null,
            // Elevation is an edge plus ambient darkness, never a coloured
            // glow — DESIGN.md #4.
            boxShadow: _cardFocused ? AppElevation.raised : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 106.du(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(
                      imageUrl: PlexImageUrl.of(widget.server, room.thumb),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppGradients.linear(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14.du(context),
                      right: 14.du(context),
                      bottom: 14.du(context),
                      child: AppText(
                        room.title,
                        color: AppColors.inkOnArt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isHosted || widget.isMine)
                      Positioned(
                        top: 10.du(context),
                        right: 10.du(context),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.du(context),
                            vertical: 5.du(context),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(50.du(context)),
                          ),
                          child: AppText(
                            widget.isHosted ? "You're hosting" : "You're in",
                            color: AppColors.inkOnArt,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(14.du(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34.du(context),
                          height: 34.du(context),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent.withValues(alpha: 0.35),
                          ),
                          alignment: Alignment.center,
                          child: AppText(
                            room.hostName.isNotEmpty
                                ? room.hostName[0].toUpperCase()
                                : '?',
                            color: AppColors.inkOnArt,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(width: 10.du(context)),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppText(
                                widget.isHosted
                                    ? 'You hosting'
                                    : '${room.hostName} hosting',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4.du(context)),
                              AppText(
                                '${room.occupants} of ${room.maxSeats} watching',
                                color: AppColors.ink3,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.du(context)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6.du(context),
                          height: 6.du(context),
                          decoration: BoxDecoration(
                            color: widget.isHosted && _failed
                                ? AppColors.ink3
                                : AppColors.accent,
                            borderRadius: BorderRadius.circular(50.du(context)),
                          ),
                        ),
                        SizedBox(width: 8.du(context)),
                        Flexible(
                          child: AppText(
                            'Available on ${widget.merged.relay.nickname}',
                            color: AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.du(context)),
                    if (widget.isHosted && _failed)
                      AppText("Can't reach relay", color: AppColors.ink3)
                    else
                      // Wrap, not Row: "Join"/"Rejoin" + "End session" side
                      // by side can be wider than the 300px card allows
                      // (so this drops to a second line instead of
                      // overflowing).
                      Wrap(
                        spacing: 16.du(context),
                        runSpacing: 8.du(context),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Focus(
                            canRequestFocus: false,
                            onKeyEvent: (node, event) =>
                                event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowUp
                                ? KeyEventResult.handled
                                : KeyEventResult.ignored,
                            child: AppButton(
                              onClick: widget.onClick,
                              enabled: !full,
                              compact: true,
                              focusNode: _joinFocusNode,
                              autofocus: widget.autofocus,
                              child: AppText(joinLabel),
                            ),
                          ),
                          if (widget.isHosted)
                            Focus(
                              canRequestFocus: false,
                              // Unlike Join's plain trap, this can't just
                              // swallow arrowUp: whether "End session" ends
                              // up on the same line as Join or wraps below
                              // it (see the Wrap comment above) depends on
                              // the join label's width, so a blind trap
                              // here sometimes blocks the legitimate
                              // End-session -> Join move. Route it directly
                              // to Join's own node instead of guessing the
                              // current layout.
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent ||
                                    event.logicalKey !=
                                        LogicalKeyboardKey.arrowUp) {
                                  return KeyEventResult.ignored;
                                }
                                _joinFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              },
                              child: AppOutlinedButton(
                                onClick: _endNow,
                                compact: true,
                                child: const AppText('End session'),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverflowTile extends StatelessWidget {
  final int count;
  final VoidCallback onClick;

  const _OverflowTile({required this.count, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132.du(context),
      height: 212.du(context),
      child: AppCard(
        onClick: onClick,
        shape: _roomCardShape(context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText('+$count', style: AppTypography.rowLabel),
              AppText('more rooms', color: AppColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
