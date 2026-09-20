import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/text.dart';
import '../../sync/relay_protocol.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

const _visibleRoomCards = 3;
const _roomCardSpring = SpringDescription(mass: 1, stiffness: 400, damping: 30);

/// One live room, merged with the relay entry that's hosting it. Ports
/// HomeScreen.kt's `MergedRoom`.
class MergedRoom {
  final RelayEntry relay;
  final RelayRoomSummary room;

  const MergedRoom(this.relay, this.room);
}

/// Ports HomeScreen.kt's `WatchTogetherRow`.
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
          padding: const EdgeInsets.only(left: 32, top: 32, bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent)),
              const SizedBox(width: 12),
              const AppText('Watch Together', style: AppTypography.titleLarge),
              const SizedBox(width: 12),
              AppText(
                '${rooms.length} room${rooms.length == 1 ? '' : 's'} live · $relayCount relay${relayCount == 1 ? '' : 's'}',
                color: AppColors.onSurfaceVariant,
              ),
            ],
          ),
        ),
        SizedBox(
          // Tall enough for RoomCard's real content height (image + two
          // text rows + button row + padding) — Kotlin's LazyRow here has
          // no fixed height at all (Column gives it intrinsic sizing), but
          // Flutter's horizontal ListView needs a bounded cross-axis
          // height, so this picks one with headroom rather than the
          // arbitrary 260 that clipped the card. +12 further for
          // EdgeFadeRow's ShaderMask bounds — see the matching comment on
          // Continue Watching's SizedBox in home_screen.dart.
          height: 332,
          child: EdgeFadeRow(
          child: ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            // See the matching comment on Home's rows — Flutter's ListView
            // clips its children by default where Compose's LazyRow doesn't,
            // and RoomCard also has a focus-scale that can bleed past its
            // own bounds.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 10),
            itemCount: rooms.length + (rooms.length > _visibleRoomCards ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(width: 20),
            itemBuilder: (context, index) {
              if (index >= rooms.length) {
                return _OverflowTile(
                  count: rooms.length - _visibleRoomCards,
                  onClick: () => scrollController.animateTo(
                    _visibleRoomCards * 320.0,
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
      ],
    );
  }
}

const _roomCardShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));

/// Ports HomeScreen.kt's `RoomCard` — hand-rolls its own focus tracking
/// (not FocusableSurface) so it can layer the scale/glow/border exactly
/// like Card.kt while still hosting two independently-focusable buttons
/// inside. Explicitly scrolls itself into view on focus via
/// Scrollable.ensureVisible — Flutter's Scrollable doesn't auto-scroll on
/// descendant focus by default (unlike Compose's opt-out
/// suppressAncestorBringIntoView had to fight), so there's no ancestor
/// double-scroll to suppress here, just this card's own explicit call.
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

class _RoomCardState extends State<RoomCard> with SingleTickerProviderStateMixin {
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
    _scaleController = AnimationController(value: 1, vsync: this, upperBound: 1.04);
    _ownsJoinFocusNode = widget.joinFocusNode == null;
    _joinFocusNode = widget.joinFocusNode ?? FocusNode(debugLabel: 'room-card-join');
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
    _scaleController.animateWith(SpringSimulation(_roomCardSpring, _scaleController.value, target, 0));
    if (hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final renderObject = context.findRenderObject();
        // alignment: 0.8, matching Home's rows — see AppCard._handleFocusChange.
        if (renderObject != null) Scrollable.ensureVisible(context, alignment: 0.8, duration: const Duration(milliseconds: 200));
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
        if (mounted && _failedResetToken == token) setState(() => _failed = false);
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
        builder: (context, child) => Transform.scale(scale: _scaleController.value, child: child),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: _cardFocused ? Border.all(color: AppColors.accent, width: 2) : null,
            boxShadow: _cardFocused
                ? [BoxShadow(color: AppColors.accentGlow.withValues(alpha: 0.22), blurRadius: 28)]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 106,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(imageUrl: PlexImageUrl.of(widget.server, room.thumb)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.transparent, Color(0xD9000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: AppText(room.title, color: AppColors.white, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (widget.isHosted || widget.isMine)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(50)),
                          child: AppText(
                            widget.isHosted ? "You're hosting" : "You're in",
                            color: AppColors.white,
                            style: const TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.35)),
                          alignment: Alignment.center,
                          child: AppText(
                            room.hostName.isNotEmpty ? room.hostName[0].toUpperCase() : '?',
                            color: AppColors.white,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppText(
                                widget.isHosted ? 'You hosting' : '${room.hostName} hosting',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              AppText('${room.occupants} of ${room.maxSeats} watching', color: AppColors.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: widget.isHosted && _failed ? AppColors.onSurfaceVariant : AppColors.accent,
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: AppText('Available on ${widget.merged.relay.nickname}', color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.isHosted && _failed)
                      const AppText("Can't reach relay", color: AppColors.onSurfaceVariant)
                    else
                      // Wrap, not Row: "Join"/"Rejoin" + "End session" side
                      // by side can be wider than the 300px card allows
                      // (Compose's Row silently overflows here rather than
                      // asserting; Flutter's doesn't, so this drops to a
                      // second line instead of hard-overflowing).
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Focus(
                            canRequestFocus: false,
                            onKeyEvent: (node, event) => event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp
                                ? KeyEventResult.handled
                                : KeyEventResult.ignored,
                            child: AppButton(onClick: widget.onClick, enabled: !full, compact: true, focusNode: _joinFocusNode, autofocus: widget.autofocus, child: AppText(joinLabel)),
                          ),
                          if (widget.isHosted)
                            Focus(
                              canRequestFocus: false,
                              onKeyEvent: (node, event) => event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp
                                  ? KeyEventResult.handled
                                  : KeyEventResult.ignored,
                              child: AppOutlinedButton(onClick: _endNow, compact: true, child: const AppText('End session')),
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
      width: 132,
      height: 212,
      child: AppCard(
        onClick: onClick,
        shape: _roomCardShape,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText('+$count', style: AppTypography.headlineMedium),
              const AppText('more rooms', color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
