import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide ConnectionState;

import '../../data/media/artwork_url.dart';
import '../../data/media/media_models.dart';
import '../../data/media/media_server.dart';
import '../../theme/phosphor_icons.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../sync/relay_client.dart';
import '../../sync/relay_protocol.dart';
import '../../sync/relay_urls.dart';
import '../../sync/time_utils.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../home/watch_together_bar.dart' show EndRoomConfirm;
import '../common/artwork.dart';
import '../common/chat_overlay.dart';
import '../common/relay_status.dart';

const _presenceIntervalMs = 3000;
const _rosterStaleMs = _presenceIntervalMs * 3;
const _roomSeatCap = 8;
const _pinnedLastSeenMs = 1 << 62;
const _visibleSeats = 5;

class _RosterEntry {
  final String username;
  final String? avatarUrl;
  final int lastSeenMs;

  const _RosterEntry(this.username, this.avatarUrl, this.lastSeenMs);
}

/// The pre-playback waiting room: live
/// roster driven by presence events over [RelayClient.events], a chat QR
/// modal, and the relay connection status line/dot.
class LobbyScreen extends StatefulWidget {
  final MediaServer server;
  final MediaDetail detail;
  final String localUsername;
  final String? localAvatarUrl;
  final String hostName;
  final String relayNickname;
  final Future<int?> Function()? measureLatency;
  final RelayClient relay;
  final ChatOverlayCorner chatOverlayCorner;

  /// Phone chat is on (Settings): the lobby shows the QR that opens it.
  final bool phoneChat;
  final VoidCallback? onHostOnAnother;
  final ValueChanged<bool> onStart;
  final VoidCallback onBack;

  /// The host's "Close the room": ends it for everyone (Back only steps
  /// away and keeps it open). Null for guests, who leave instead.
  final VoidCallback? onEndRoom;

  const LobbyScreen({
    super.key,
    required this.server,
    required this.detail,
    required this.localUsername,
    this.localAvatarUrl,
    required this.hostName,
    required this.relayNickname,
    this.measureLatency,
    required this.relay,
    this.chatOverlayCorner = ChatOverlayCorner.bottomEnd,
    this.phoneChat = true,
    this.onHostOnAnother,
    required this.onStart,
    required this.onBack,
    this.onEndRoom,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late RelayStatusTracker _statusTracker;
  late StreamSubscription<ConnectionState> _connectionSub;
  late StreamSubscription<int?> _seatSub;
  late StreamSubscription<String?> _roomIdSub;
  late StreamSubscription<RelayEvent> _eventsSub;
  final _chatMessages = StreamController<ChatMessage>.broadcast();

  Timer? _presenceTimer;
  Timer? _rosterPruneTimer;
  Timer? _latencyTimer;
  int? _latencyMs;
  Map<String, _RosterEntry> _roster = {};
  late ConnectionState _connectionState;
  int? _seatIndex;
  String? _roomId;

  bool get _isHost => _seatIndex == 0;

  final _startFocus = FocusNode(debugLabel: 'lobby-start');
  final _closeFocus = FocusNode(debugLabel: 'lobby-close');
  final _keepOpenFocus = FocusNode(debugLabel: 'lobby-keep-open');
  bool _confirmingEnd = false;

  /// Close the room: at once if nobody has joined; asked first if someone
  /// has, since it ends their evening too.
  void _closeRoom() {
    final end = widget.onEndRoom;
    if (!_isHost || end == null) {
      widget.onBack();
      return;
    }
    if (_roster.isEmpty) {
      end();
      return;
    }
    setState(() => _confirmingEnd = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keepOpenFocus.requestFocus();
    });
  }

  void _keepOpen() {
    setState(() => _confirmingEnd = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    // Nothing here claims focus on its own — without this, the nav rail
    // (still focused from whatever screen led into the lobby) keeps focus
    // forever, same root cause as the Settings/Relay-settings/Seasons
    // "opens the nav drawer" bugs fixed elsewhere this session.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startFocus.requestFocus(),
    );
    _connectionState = widget.relay.connectionStateValue;
    _seatIndex = widget.relay.seatIndexValue;
    _statusTracker = RelayStatusTracker(
      widget.relay.connectionState,
      initial: _connectionState,
    );

    _connectionSub = widget.relay.connectionState.listen((state) {
      setState(() => _connectionState = state);
      if (state == ConnectionState.roomClosed ||
          state == ConnectionState.roomNotFound)
        widget.onBack();
      _restartPresenceLoop();
    });
    _seatSub = widget.relay.seatIndex.listen((seat) {
      setState(() => _seatIndex = seat);
      _restartPresenceLoop();
    });
    _roomIdSub = widget.relay.roomId.listen(
      (id) => setState(() => _roomId = id),
    );
    _eventsSub = widget.relay.events.listen(_handleEvent);

    _rosterPruneTimer = Timer.periodic(
      const Duration(milliseconds: _presenceIntervalMs),
      (_) => _pruneRoster(),
    );
    _restartPresenceLoop();
    if (widget.measureLatency != null) {
      _measureLatency();
      _latencyTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _measureLatency(),
      );
    }
  }

  Future<void> _measureLatency() async {
    final ms = await widget.measureLatency?.call();
    if (mounted) setState(() => _latencyMs = ms);
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
    _connectionSub.cancel();
    _seatSub.cancel();
    _roomIdSub.cancel();
    _eventsSub.cancel();
    _presenceTimer?.cancel();
    _rosterPruneTimer?.cancel();
    _chatMessages.close();
    _statusTracker.dispose();
    _startFocus.dispose();
    _closeFocus.dispose();
    _keepOpenFocus.dispose();
    super.dispose();
  }

  void _restartPresenceLoop() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    if (_isHost || _connectionState != ConnectionState.connected) return;
    _sendPresence();
    _presenceTimer = Timer.periodic(
      const Duration(milliseconds: _presenceIntervalMs),
      (_) => _sendPresence(),
    );
  }

  void _sendPresence() {
    widget.relay.send(
      RelayEvent(
        kind: 'presence',
        fromPeerId: widget.relay.myPeerId,
        username: widget.localUsername,
        avatarUrl: widget.localAvatarUrl,
      ),
    );
  }

  void _pruneRoster() {
    final cutoff = nowMs() - _rosterStaleMs;
    setState(
      () => _roster = {
        for (final e in _roster.entries)
          if (e.value.lastSeenMs >= cutoff) e.key: e.value,
      },
    );
  }

  /// The host's peer id, once a playback state names it — a host already
  /// watching announces itself like anyone else, and has its own seat.
  String? _hostPeerId;

  bool _started = false;

  void _startOnce() {
    if (_started) return;
    _started = true;
    widget.onStart(false);
  }

  void _handleEvent(RelayEvent event) {
    switch (event.kind) {
      case 'playbackState':
        final host = event.fromPeerId;
        if (host != null && host != _hostPeerId) {
          setState(() {
            _hostPeerId = host;
            _roster = {..._roster}..remove(host);
          });
        }
        // The host is already watching (it plays out a state as soon as it
        // hears from someone new): straight into the player — the room
        // holds for this guest to open and catch up, then plays on.
        if (!_isHost && event.phase != null && event.phase != 'loading') {
          _startOnce();
        }
      case 'presence':
        final fromPeerId = event.fromPeerId;
        if (fromPeerId == null || fromPeerId == widget.relay.myPeerId) return;
        if (fromPeerId == _hostPeerId) return;
        setState(
          () => _roster = {
            ..._roster,
            fromPeerId: _RosterEntry(
              event.username ?? 'Guest',
              event.avatarUrl,
              nowMs(),
            ),
          },
        );
      case 'start':
        _startOnce();
      case 'chat':
        _chatMessages.add(relayEventToChatMessage(event));
    }
  }

  void _handleBack() {
    widget.onBack();
  }

  Alignment _cornerAlignment(ChatOverlayCorner corner) => switch (corner) {
    ChatOverlayCorner.topStart => Alignment.topLeft,
    ChatOverlayCorner.topEnd => Alignment.topRight,
    ChatOverlayCorner.bottomStart => Alignment.bottomLeft,
    ChatOverlayCorner.bottomEnd => Alignment.bottomRight,
  };

  void _start({required bool restart}) {
    widget.relay.send(
      RelayEvent(
        kind: 'start',
        fromPeerId: widget.relay.myPeerId,
        username: widget.localUsername,
      ),
    );
    widget.onStart(restart);
  }

  @override
  Widget build(BuildContext context) {
    final others = <_RosterEntry>[
      if (!_isHost)
        _RosterEntry(
          widget.localUsername,
          widget.localAvatarUrl,
          _pinnedLastSeenMs,
        ),
      ...(_roster.values.toList()
        ..sort((a, b) => a.lastSeenMs.compareTo(b.lastSeenMs))),
    ];
    final canRestart = _isHost && (widget.detail.viewOffset ?? 0) > 0;
    final seated = others.length + 1;
    // Screen 10: empty seats are drawn, not implied — enough to show more
    // are coming (five circles in all), never more than the room holds.
    final emptySeats = math.min(
      _roomSeatCap - seated,
      math.max(1, _visibleSeats - seated),
    );
    final roomLabel = _isHost
        ? 'YOUR ROOM'
        : '${widget.hostName.toUpperCase()}’S ROOM';

    return BackHandler(
      onBack: _handleBack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            imageUrl: ArtworkUrl.of(
              widget.server,
              widget.detail.art ?? widget.detail.thumb,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.linear(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.72),
                  AppColors.canvas.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(64.du(context)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      PhosphorIconsRegular.usersThree,
                      size: 26,
                      tint: AppColors.accent300,
                    ),
                    SizedBox(width: 14.du(context)),
                    AppText(
                      '$roomLabel · $seated OF $_roomSeatCap SEATS',
                      style: AppTypography.micro,
                      color: AppColors.accent300,
                    ),
                  ],
                ),
                SizedBox(height: 14.du(context)),
                AppText(
                  widget.detail.title,
                  style: AppTypography.display,
                  color: AppColors.inkOnArt,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 14.du(context)),
                ValueListenableBuilder<RelayStatus>(
                  valueListenable: _statusTracker.status,
                  builder: (context, status, _) => _StatusLine(
                    status: status,
                    relayNickname: widget.relayNickname,
                    latencyMs: _latencyMs,
                    startAtMs: widget.detail.viewOffset ?? 0,
                  ),
                ),
                SizedBox(height: 56.du(context)),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Seat(
                        name: widget.hostName,
                        avatarUrl: _isHost ? widget.localAvatarUrl : null,
                        role: _isHost ? 'Host · you' : 'Host',
                        roleColor: AppColors.accent300,
                      ),
                      for (final entry in others) ...[
                        SizedBox(width: 56.du(context)),
                        _Seat(
                          name: entry.username,
                          avatarUrl: entry.avatarUrl,
                          role: entry.lastSeenMs == _pinnedLastSeenMs
                              ? 'You'
                              : 'Ready',
                          roleColor: entry.lastSeenMs == _pinnedLastSeenMs
                              ? AppColors.accent300
                              : AppColors.success,
                        ),
                      ],
                      for (var i = 0; i < emptySeats; i++) ...[
                        SizedBox(width: 56.du(context)),
                        const _Seat.empty(),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 56.du(context)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      onClick: () => _start(restart: false),
                      focusNode: _startFocus,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(PhosphorIconsFill.play, size: 22),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText(
                            'Start for everyone',
                            style: AppTypography.label,
                            color: null,
                          ),
                        ],
                      ),
                    ),
                    if (canRestart) ...[
                      SizedBox(width: 16.du(context)),
                      AppOutlinedButton(
                        onClick: () => _start(restart: true),
                        child: const AppIcon(
                          PhosphorIconsRegular.arrowCounterClockwise,
                          size: 22,
                        ),
                      ),
                    ],
                    SizedBox(width: 16.du(context)),
                    AppOutlinedButton(
                      onClick: _closeRoom,
                      focusNode: _closeFocus,
                      child: AppText(
                        _isHost ? 'Close the room' : 'Leave the room',
                        style: AppTypography.label,
                        color: null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.phoneChat)
            Align(
              alignment: _cornerAlignment(widget.chatOverlayCorner),
              child: Padding(
                padding: EdgeInsets.all(48.du(context)),
                child: SizedBox(
                  width: 520.du(context),
                  child: ChatOverlay(
                    messages: _chatMessages.stream,
                    corner: widget.chatOverlayCorner,
                  ),
                ),
              ),
            ),
          // Only the states the header line can't carry on its own: the
          // slow-wake explanation and the failure actions.
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(48.du(context)),
              child: FractionallySizedBox(
                widthFactor: 0.45,
                alignment: Alignment.centerLeft,
                child: ValueListenableBuilder<RelayStatus>(
                  valueListenable: _statusTracker.status,
                  builder: (context, status, _) =>
                      status == RelayStatus.waking ||
                          status == RelayStatus.failed
                      ? RelayStatusLine(
                          status: status,
                          relayNickname: widget.relayNickname,
                          onRetry: widget.relay.retryNow,
                          onHostOnAnother: widget.onHostOnAnother,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (_confirmingEnd)
            EndRoomConfirm(
              keepOpenFocus: _keepOpenFocus,
              onKeepOpen: _keepOpen,
              onEndForEveryone: () {
                setState(() => _confirmingEnd = false);
                widget.onEndRoom?.call();
              },
            ),
          // Phone chat's QR sits in a top corner, clear of the corner the
          // messages arrive in — no button, no modal: whoever is in the
          // room can scan it while everyone gathers.
          if (widget.phoneChat)
            Align(
              alignment: widget.chatOverlayCorner == ChatOverlayCorner.topEnd
                  ? Alignment.topLeft
                  : Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.all(48.du(context)),
                child: _ChatQrCard(
                  relayUrl: widget.relay.relayUrl,
                  roomId: _roomId,
                  defaultName: widget.localUsername,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Relay connected · 38 ms · starting at 46:12" — the relay's health is
/// half of what people in the room are waiting on.
class _StatusLine extends StatelessWidget {
  final RelayStatus status;
  final String relayNickname;
  final int? latencyMs;
  final int startAtMs;

  const _StatusLine({
    required this.status,
    required this.relayNickname,
    required this.latencyMs,
    required this.startAtMs,
  });

  @override
  Widget build(BuildContext context) {
    final (dot, text) = switch (status) {
      RelayStatus.connectedConfirm || RelayStatus.dotOnly => (
        AppColors.success,
        [
          '$relayNickname connected',
          if (latencyMs != null) '$latencyMs ms',
          startAtMs > 0
              ? 'starting at ${_clock(startAtMs)}'
              : 'starting from the beginning',
        ].join(' · '),
      ),
      RelayStatus.silent || RelayStatus.waking => (
        AppColors.warning,
        'Connecting to $relayNickname…',
      ),
      RelayStatus.reconnecting => (
        AppColors.warning,
        'Reconnecting to $relayNickname…',
      ),
      RelayStatus.failed => (AppColors.error, 'Can’t reach $relayNickname'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9.du(context),
          height: 9.du(context),
          decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
        ),
        SizedBox(width: 14.du(context)),
        AppText(text, style: AppTypography.label, color: AppColors.ink2),
      ],
    );
  }

  static String _clock(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }
}

/// The phone chat QR, in the lobby's corner: scan it to chat from a phone.
class _ChatQrCard extends StatelessWidget {
  final String relayUrl;
  final String? roomId;
  final String defaultName;

  const _ChatQrCard({
    required this.relayUrl,
    this.roomId,
    required this.defaultName,
  });

  @override
  Widget build(BuildContext context) {
    final id = roomId;
    final chatUrl = id != null
        ? relayUrlToChatUrl(
            relayUrl,
            id,
            defaultName,
            themeId: AppColors.currentTheme.name,
          )
        : null;
    if (chatUrl == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(AppSpacing.lg.du(context)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 150.du(context),
            height: 150.du(context),
            color: AppColors.inkOnArt,
            padding: EdgeInsets.all(AppSpacing.sm.du(context)),
            child: QrImageView(
              data: chatUrl,
              backgroundColor: AppColors.inkOnArt,
            ),
          ),
          SizedBox(height: AppSpacing.md.du(context)),
          AppText(
            'Scan to chat',
            style: AppTypography.caption,
            color: AppColors.ink2,
          ),
        ],
      ),
    );
  }
}

/// One seat in the room: a 130 circle (avatar, initial, or dashed when
/// empty), the name, and a coloured role line.
class _Seat extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  final String? role;
  final Color? roleColor;

  const _Seat({
    required String this.name,
    this.avatarUrl,
    required String this.role,
    required Color this.roleColor,
  });

  const _Seat.empty()
    : name = null,
      avatarUrl = null,
      role = null,
      roleColor = null;

  @override
  Widget build(BuildContext context) {
    final size = 130.du(context);
    final name = this.name;
    final avatar = avatarUrl;
    final Widget circle;
    if (name == null) {
      circle = SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _EmptySeatPainter(1.du(context))),
      );
    } else {
      circle = Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.lineStrong, width: 2.du(context)),
        ),
        child: avatar != null
            ? Image.network(
                avatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initial(context, name),
              )
            : _initial(context, name),
      );
    }
    return SizedBox(
      width: 180.du(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          SizedBox(height: 14.du(context)),
          AppText(
            name ?? 'Empty seat',
            style: AppTypography.rowLabel,
            color: name == null ? AppColors.ink3 : AppColors.inkOnArt,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
          if (role != null) ...[
            SizedBox(height: 4.du(context)),
            AppText(role!, style: AppTypography.caption, color: roleColor),
          ],
        ],
      ),
    );
  }

  Widget _initial(BuildContext context, String name) => AppText(
    name.isNotEmpty ? name[0].toUpperCase() : '?',
    style: AppTypography.title1,
    color: AppColors.inkOnArt,
  );
}

class _EmptySeatPainter extends CustomPainter {
  final double scale;

  const _EmptySeatPainter(this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 2 * scale;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = AppColors.ink.withValues(alpha: 0.04),
    );

    final dashLength = 8.0 * scale;
    final gapLength = 6.0 * scale;
    final circumference = 2 * math.pi * radius;
    final dashCount = math.max(
      1,
      (circumference / (dashLength + gapLength)).floor(),
    );
    final anglePerDash = 2 * math.pi / dashCount;
    final dashSweep = anglePerDash * (dashLength / (dashLength + gapLength));
    final dashPaint = Paint()
      // Brighter than the mockup's lineStrong: this sits on the title's
      // own backdrop, not a flat ground, and has to survive bright art.
      ..color = AppColors.ink3
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, i * anglePerDash, dashSweep, false, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmptySeatPainter oldDelegate) => true;
}
