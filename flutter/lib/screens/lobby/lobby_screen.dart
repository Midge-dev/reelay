import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../sync/relay_client.dart';
import '../../sync/relay_protocol.dart';
import '../../sync/relay_urls.dart';
import '../../sync/time_utils.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/chat_overlay.dart';
import '../common/relay_status.dart';
import '../common/watch_together_icon.dart';

const _presenceIntervalMs = 3000;
const _rosterStaleMs = _presenceIntervalMs * 3;
const _roomSeatCap = 8;
const _pinnedLastSeenMs = 1 << 62;

class _RosterEntry {
  final String username;
  final String? avatarUrl;
  final int lastSeenMs;

  const _RosterEntry(this.username, this.avatarUrl, this.lastSeenMs);
}

/// Ports ui/lobby/LobbyScreen.kt — the pre-playback waiting room: live
/// roster driven by presence events over [RelayClient.events], a chat QR
/// modal, and the relay connection status line/dot.
class LobbyScreen extends StatefulWidget {
  final PlexServer server;
  final PlexMovieDetail detail;
  final String localUsername;
  final String? localAvatarUrl;
  final String hostName;
  final String relayNickname;
  final RelayClient relay;
  final ChatOverlayCorner chatOverlayCorner;
  final VoidCallback? onHostOnAnother;
  final ValueChanged<bool> onStart;
  final VoidCallback onBack;

  const LobbyScreen({
    super.key,
    required this.server,
    required this.detail,
    required this.localUsername,
    this.localAvatarUrl,
    required this.hostName,
    required this.relayNickname,
    required this.relay,
    this.chatOverlayCorner = ChatOverlayCorner.bottomEnd,
    this.onHostOnAnother,
    required this.onStart,
    required this.onBack,
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
  Map<String, _RosterEntry> _roster = {};
  bool _showChatModal = false;
  late ConnectionState _connectionState;
  int? _seatIndex;
  String? _roomId;

  bool get _isHost => _seatIndex == 0;

  final _startFocus = FocusNode(debugLabel: 'lobby-start');

  @override
  void initState() {
    super.initState();
    // Nothing here claims focus on its own — without this, the nav rail
    // (still focused from whatever screen led into the lobby) keeps focus
    // forever, same root cause as the Settings/Relay-settings/Seasons
    // "opens the nav drawer" bugs fixed elsewhere this session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFocus.requestFocus());
    _connectionState = widget.relay.connectionStateValue;
    _seatIndex = widget.relay.seatIndexValue;
    _statusTracker = RelayStatusTracker(widget.relay.connectionState, initial: _connectionState);

    _connectionSub = widget.relay.connectionState.listen((state) {
      setState(() => _connectionState = state);
      if (state == ConnectionState.roomClosed || state == ConnectionState.roomNotFound) widget.onBack();
      _restartPresenceLoop();
    });
    _seatSub = widget.relay.seatIndex.listen((seat) {
      setState(() => _seatIndex = seat);
      _restartPresenceLoop();
    });
    _roomIdSub = widget.relay.roomId.listen((id) => setState(() => _roomId = id));
    _eventsSub = widget.relay.events.listen(_handleEvent);

    _rosterPruneTimer = Timer.periodic(const Duration(milliseconds: _presenceIntervalMs), (_) => _pruneRoster());
    _restartPresenceLoop();
  }

  @override
  void dispose() {
    _connectionSub.cancel();
    _seatSub.cancel();
    _roomIdSub.cancel();
    _eventsSub.cancel();
    _presenceTimer?.cancel();
    _rosterPruneTimer?.cancel();
    _chatMessages.close();
    _statusTracker.dispose();
    _startFocus.dispose();
    super.dispose();
  }

  void _restartPresenceLoop() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    if (_isHost || _connectionState != ConnectionState.connected) return;
    _sendPresence();
    _presenceTimer = Timer.periodic(const Duration(milliseconds: _presenceIntervalMs), (_) => _sendPresence());
  }

  void _sendPresence() {
    widget.relay.send(RelayEvent(
      kind: 'presence',
      fromPeerId: widget.relay.myPeerId,
      username: widget.localUsername,
      avatarUrl: widget.localAvatarUrl,
    ));
  }

  void _pruneRoster() {
    final cutoff = nowMs() - _rosterStaleMs;
    setState(() => _roster = {for (final e in _roster.entries) if (e.value.lastSeenMs >= cutoff) e.key: e.value});
  }

  void _handleEvent(RelayEvent event) {
    switch (event.kind) {
      case 'presence':
        final fromPeerId = event.fromPeerId;
        if (fromPeerId == null || fromPeerId == widget.relay.myPeerId) return;
        setState(() => _roster = {..._roster, fromPeerId: _RosterEntry(event.username ?? 'Guest', event.avatarUrl, nowMs())});
      case 'start':
        widget.onStart(false);
      case 'chat':
        _chatMessages.add(relayEventToChatMessage(event));
    }
  }

  void _handleBack() {
    if (_showChatModal) {
      setState(() => _showChatModal = false);
    } else {
      widget.onBack();
    }
  }

  Alignment _cornerAlignment(ChatOverlayCorner corner) => switch (corner) {
        ChatOverlayCorner.topStart => Alignment.topLeft,
        ChatOverlayCorner.topEnd => Alignment.topRight,
        ChatOverlayCorner.bottomStart => Alignment.bottomLeft,
        ChatOverlayCorner.bottomEnd => Alignment.bottomRight,
      };

  @override
  Widget build(BuildContext context) {
    final others = <_RosterEntry>[
      if (!_isHost) _RosterEntry(widget.localUsername, widget.localAvatarUrl, _pinnedLastSeenMs),
      ...(_roster.values.toList()..sort((a, b) => a.lastSeenMs.compareTo(b.lastSeenMs))),
    ];
    final canRestart = _isHost && (widget.detail.viewOffset ?? 0) > 0;

    return BackHandler(
      onBack: _handleBack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(imageUrl: PlexImageUrl.of(widget.server, widget.detail.art ?? widget.detail.thumb)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background.withValues(alpha: 0.62), AppColors.background.withValues(alpha: 0.92)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const WatchTogetherIcon(),
                    const SizedBox(width: 16),
                    AppText(widget.detail.title, style: AppTypography.title1, color: AppColors.inkOnArt),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ValueListenableBuilder<RelayStatus>(
                        valueListenable: _statusTracker.status,
                        builder: (context, status, _) => RelayStatusDot(status: status),
                      ),
                      const SizedBox(width: 10),
                      AppText(widget.relayNickname, color: AppColors.inkOnArt.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _LobbyPersonCard(
                        name: widget.hostName,
                        avatarUrl: _isHost ? widget.localAvatarUrl : null,
                        subtitle: 'host',
                      ),
                      for (final entry in others) ...[
                        const SizedBox(width: 64),
                        _LobbyPersonCard(name: entry.username, avatarUrl: entry.avatarUrl),
                      ],
                      if (others.length + 1 < _roomSeatCap) ...[const SizedBox(width: 64), const _EmptySeat()],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        onClick: () {
                          widget.relay.send(RelayEvent(kind: 'start', fromPeerId: widget.relay.myPeerId, username: widget.localUsername));
                          widget.onStart(false);
                        },
                        focusNode: _startFocus,
                        child: const AppText('Start'),
                      ),
                      if (canRestart) ...[
                        const SizedBox(width: 24),
                        AppButton(
                          onClick: () {
                            widget.relay.send(RelayEvent(kind: 'start', fromPeerId: widget.relay.myPeerId, username: widget.localUsername));
                            widget.onStart(true);
                          },
                          child: const AppIcon(Icons.replay, tint: AppColors.inkOnArt, size: 22),
                        ),
                      ],
                      const SizedBox(width: 24),
                      AppButton(onClick: () => setState(() => _showChatModal = true), child: const AppText('Chat QR code')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: _cornerAlignment(widget.chatOverlayCorner),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                alignment: _cornerAlignment(widget.chatOverlayCorner),
                child: ChatOverlay(messages: _chatMessages.stream, corner: widget.chatOverlayCorner),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: FractionallySizedBox(
                widthFactor: 0.6,
                alignment: Alignment.centerLeft,
                child: ValueListenableBuilder<RelayStatus>(
                  valueListenable: _statusTracker.status,
                  builder: (context, status, _) => RelayStatusLine(
                    status: status,
                    relayNickname: widget.relayNickname,
                    onRetry: widget.relay.retryNow,
                    onHostOnAnother: widget.onHostOnAnother,
                  ),
                ),
              ),
            ),
          ),
          if (_showChatModal)
            _ChatQrModal(
              relayUrl: widget.relay.relayUrl,
              roomId: _roomId,
              defaultName: widget.localUsername,
              onDismiss: () => setState(() => _showChatModal = false),
            ),
        ],
      ),
    );
  }
}

class _ChatQrModal extends StatelessWidget {
  final String relayUrl;
  final String? roomId;
  final String defaultName;
  final VoidCallback onDismiss;

  const _ChatQrModal({required this.relayUrl, this.roomId, required this.defaultName, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final id = roomId;
    final chatUrl = id != null ? relayUrlToChatUrl(relayUrl, id, defaultName) : null;

    return Positioned.fill(
      child: ColoredBox(
        color: AppScrims.dialog.withValues(alpha: 0.85),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: AppColors.surface),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppText('Join the chat', style: AppTypography.title2, color: AppColors.inkOnArt),
                      if (chatUrl == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: AppText('Still connecting to the room — try again in a moment.', color: AppColors.inkOnArt),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Container(
                            width: 220,
                            height: 220,
                            color: AppColors.inkOnArt,
                            padding: const EdgeInsets.all(12),
                            child: QrImageView(data: chatUrl, backgroundColor: AppColors.inkOnArt),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: AppText('Scan with your phone, or visit:', color: AppColors.inkOnArt),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AppText(chatUrl, color: AppColors.inkOnArt, style: AppTypography.body),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: AppOutlinedButton(onClick: onDismiss, autofocus: true, child: const AppText('Close')),
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

class _LobbyPersonCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? subtitle;

  const _LobbyPersonCard({required this.name, this.avatarUrl, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final avatar = avatarUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.35)),
          alignment: Alignment.center,
          child: avatar != null
              ? ClipOval(child: Image.network(avatar, width: 96, height: 96, fit: BoxFit.cover))
              : AppText(name.isNotEmpty ? name[0].toUpperCase() : '?', style: AppTypography.title2, color: AppColors.inkOnArt),
        ),
        Padding(padding: const EdgeInsets.only(top: 12), child: AppText(name, color: AppColors.inkOnArt)),
        if (subtitle != null) AppText(subtitle!, color: AppColors.inkOnArt.withValues(alpha: 0.6)),
      ],
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 96, height: 96, child: CustomPaint(painter: _EmptySeatPainter()));
  }
}

class _EmptySeatPainter extends CustomPainter {
  const _EmptySeatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = AppColors.inkOnArt.withValues(alpha: 0.06));

    const dashLength = 8.0;
    const gapLength = 6.0;
    final circumference = 2 * math.pi * radius;
    final dashCount = math.max(1, (circumference / (dashLength + gapLength)).floor());
    final anglePerDash = 2 * math.pi / dashCount;
    final dashSweep = anglePerDash * (dashLength / (dashLength + gapLength));
    final dashPaint = Paint()
      ..color = AppColors.inkOnArt.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, i * anglePerDash, dashSweep, false, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmptySeatPainter oldDelegate) => false;
}
