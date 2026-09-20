import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:video_player/video_player.dart';

import '../../data/plex/plex_http_client.dart';
import '../../data/plex/plex_models.dart';
import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../playback/playback_decision.dart';
import '../../playback/plex_player_factory.dart';
import '../../playback/seek_timing.dart';
import '../../playback/timeline_reporter.dart';
import '../../playback/video_player_synced_player.dart';
import '../../sync/playback_state.dart';
import '../../sync/relay_client.dart';
import '../../sync/relay_protocol.dart';
import '../../sync/relay_urls.dart';
import '../../sync/sync_view_model.dart';
import '../../theme/tokens.dart';
import '../common/app_loading_indicator.dart';
import '../common/chat_overlay.dart';
import 'chat_qr_overlay.dart';
import 'player_controls_bar.dart';
import 'player_menus.dart';

const _reportIntervalMs = 5000;
const _controlsHideDelayMs = 3000;
const _skipIncrementMs = 10000;

/// Ports ui/player/PlayerScreen.kt — the biggest platform-boundary piece of
/// this conversion. See project_flutter_full_conversion.md for the two
/// spiked risks this resolved (no play/pause reason codes, no seek-
/// discontinuity event — both handled fine by [VideoPlayerSyncedPlayer])
/// and the accepted gap (no embedded-subtitle-track selection, filtered
/// out of [subtitleOptions] rather than offered and silently broken).
///
/// Kotlin recreates the whole player (a fresh ExoPlayer) via
/// `key(playerIdentity) { PlayerSession(...) }` whenever bitrate changes,
/// but reuses the same player for a subtitle-only change while staying
/// DirectPlay (mutating ExoPlayer's TrackSelectionParameters in place).
/// This port keeps that same distinction — [_identityFor] mirrors
/// `playerIdentity` — but for a different reason: `video_player` has no
/// media-source-swap API at all (a new HLS bitrate means a new URL means a
/// new `VideoPlayerController`), while a subtitle change only means
/// re-attaching a `ClosedCaptionFile` on the *existing* controller.
class PlayerScreen extends StatefulWidget {
  final PlexServer server;
  final PlexMovieDetail detail;
  final String clientIdentifier;
  final RelayClient? relay;
  final AppSettings settings;
  final ValueChanged<int> onBitrateChanged;
  final VoidCallback onExit;

  const PlayerScreen({
    super.key,
    required this.server,
    required this.detail,
    required this.clientIdentifier,
    this.relay,
    required this.settings,
    required this.onBitrateChanged,
    required this.onExit,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final TimelineReporter _reporter;
  late final Dio _captionClient;

  late PlexPart? _resolvedPart;
  late List<SubtitleOption> _subtitleOptions;
  int? _subtitleStreamId;
  late int _maxVideoBitrateKbps;
  late PlaybackDecision _decision;
  Object? _playerIdentity;

  VideoPlayerController? _controller;
  VideoPlayerSyncedPlayer? _player;
  SyncViewModel? _sync;
  int _playerGeneration = 0;

  StreamSubscription<ConnectionState>? _connectionSub;
  StreamSubscription<PlaybackPhase?>? _phaseSub;
  StreamSubscription<List<String>>? _waitingOnSub;
  StreamSubscription<String?>? _roomIdSub;
  ConnectionState _connectionState = ConnectionState.disconnected;
  PlaybackPhase? _phase;
  List<String> _waitingOn = const [];
  String? _roomId;

  bool _controlsVisible = true;
  bool _isBuffering = false;
  bool _isPlaying = false;
  bool _subtitleMenuOpen = false;
  bool _bitrateMenuOpen = false;
  bool _chatQrOpen = false;

  int _positionMs = 0;
  int _durationMs = 0;
  double _bufferedFraction = 0;

  Timer? _controlsHideTimer;
  Timer? _reportTimer;

  final _screenFocusNode = FocusNode(debugLabel: 'player-screen');
  final _playPauseFocusNode = FocusNode(debugLabel: 'player-play-pause');

  LogicalKeyboardKey? _heldKey;
  int _heldRepeatCount = 0;

  String? get _chatUrl {
    final relay = widget.relay;
    final roomId = _roomId;
    if (relay == null || roomId == null) return null;
    return relayUrlToChatUrl(relay.relayUrl, roomId, '');
  }

  @override
  void initState() {
    super.initState();
    _reporter = TimelineReporter(widget.server, widget.clientIdentifier);
    _captionClient = plexHttpClient();

    final media = widget.detail.media.isNotEmpty ? widget.detail.media.first : null;
    _resolvedPart = media != null && media.parts.isNotEmpty ? media.parts.first : null;
    _subtitleOptions = _resolvedPart != null ? subtitleOptions(_resolvedPart!) : const [];

    final defaultId = defaultSubtitleStreamId(widget.detail);
    // Clamp to the filtered options list: a stream Plex marked "selected"
    // might be an embedded, non-burn-required track that video_player
    // can't render at all — treat that as no selection rather than a
    // phantom pick that silently shows no captions.
    _subtitleStreamId = _subtitleOptions.any((o) => o.streamId == defaultId) ? defaultId : null;

    _maxVideoBitrateKbps = widget.settings.maxVideoBitrateKbps;
    _decision = decidePlayback(widget.detail, _subtitleStreamId, forceBurn: widget.settings.forceBurnSubtitles);
    _playerIdentity = _identityFor(_decision, _maxVideoBitrateKbps);

    HardwareKeyboard.instance.addHandler(_recordInteraction);
    _reportTimer = Timer.periodic(const Duration(milliseconds: _reportIntervalMs), (_) => _reportProgress());
    _scheduleAutoHide();
    // Explicit, not autofocus: PlayerControlsBar is torn down and remounted
    // fresh (a genuine conditional-existence swap, not a Stack overlay) on
    // every hide/show, and by the time it remounts on reveal,
    // _screenFocusNode already holds focus — Flutter's autofocus declines
    // to steal focus from an already-focused scope, so it silently no-ops
    // and every subsequent D-pad press just gets swallowed by the
    // screen-level handler with the controls stuck visible but unnavigable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPauseFocusNode.requestFocus();
    });

    unawaited(_initPlayer(startPositionMs: widget.detail.viewOffset ?? 0));

    if (widget.relay != null) {
      _connectionSub = widget.relay!.connectionState.listen((state) => setState(() => _connectionState = state));
      _roomIdSub = widget.relay!.roomId.listen((id) => setState(() => _roomId = id));
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_recordInteraction);
    _controlsHideTimer?.cancel();
    _reportTimer?.cancel();
    _connectionSub?.cancel();
    _phaseSub?.cancel();
    _waitingOnSub?.cancel();
    _roomIdSub?.cancel();
    _sync?.dispose();
    _controller?.removeListener(_handleControllerTick);
    unawaited(_controller?.dispose());
    _screenFocusNode.dispose();
    _playPauseFocusNode.dispose();
    super.dispose();
  }

  Object _identityFor(PlaybackDecision decision, int maxVideoBitrateKbps) {
    return switch (decision) {
      DirectPlay() => decision.part.id,
      Transcode() => (decision.ratingKey, maxVideoBitrateKbps),
    };
  }

  Future<void> _initPlayer({required int startPositionMs}) async {
    final generation = ++_playerGeneration;
    final url = PlexPlayerFactory.mediaUrl(widget.server, _decision, _maxVideoBitrateKbps);
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await controller.initialize();
    if (!mounted || generation != _playerGeneration) {
      unawaited(controller.dispose());
      return;
    }
    if (startPositionMs > 0) await controller.seekTo(Duration(milliseconds: startPositionMs));
    await _attachCaptions(controller);
    controller.addListener(_handleControllerTick);

    final player = VideoPlayerSyncedPlayer(controller);
    final sync = SyncViewModel(player: player, relay: widget.relay);

    _phaseSub?.cancel();
    _waitingOnSub?.cancel();
    _phaseSub = sync.phase.listen((phase) => setState(() => _phase = phase));
    _waitingOnSub = sync.waitingOn.listen((waitingOn) => setState(() => _waitingOn = waitingOn));

    setState(() {
      _controller = controller;
      _player = player;
      _sync = sync;
      _isPlaying = controller.value.isPlaying;
      _durationMs = controller.value.duration.inMilliseconds;
    });
    sync.start();
    controller.play();
  }

  Future<void> _attachCaptions(VideoPlayerController controller) async {
    final part = _resolvedPart;
    if (part == null) {
      await controller.setClosedCaptionFile(null);
      return;
    }
    final source = resolveSubtitleSource(part, _subtitleStreamId);
    if (source is ExternalSubtitle) {
      await controller.setClosedCaptionFile(_fetchCaptionFile(source));
    } else {
      // NoSubtitle, or an EmbeddedSubtitle we filtered out of the picker
      // but could still reach via defaultSubtitleStreamId's clamp missing
      // an edge case — either way, nothing video_player can render.
      await controller.setClosedCaptionFile(null);
    }
  }

  Future<ClosedCaptionFile> _fetchCaptionFile(ExternalSubtitle source) async {
    final url = '${widget.server.baseUrl}${source.key}?X-Plex-Token=${widget.server.accessToken}';
    final response = await _captionClient.get<String>(url, options: Options(responseType: ResponseType.plain));
    final content = response.data ?? '';
    return content.trimLeft().startsWith('WEBVTT') ? WebVTTCaptionFile(content) : SubRipCaptionFile(content);
  }

  void _handleControllerTick() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    final buffered = value.buffered;
    final bufferedMs = buffered.isEmpty ? 0 : buffered.map((r) => r.end.inMilliseconds).reduce((a, b) => a > b ? a : b);
    setState(() {
      _isPlaying = value.isPlaying;
      _isBuffering = value.isBuffering;
      _positionMs = value.position.inMilliseconds;
      _durationMs = value.duration.inMilliseconds;
      _bufferedFraction = _durationMs > 0 ? (bufferedMs / _durationMs).clamp(0.0, 1.0) : 0.0;
    });
  }

  Future<void> _reportProgress() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.value.isPlaying ? 'playing' : 'paused';
    final duration = widget.detail.duration ?? controller.value.duration.inMilliseconds;
    await _reporter.report(widget.detail.ratingKey, state, controller.value.position.inMilliseconds, duration);
  }

  void _togglePlayPause() {
    final player = _player;
    if (player == null) return;
    if (player.isPlaying) {
      player.pause();
    } else {
      player.play();
    }
  }

  void _seekBy(int deltaMs) {
    final player = _player;
    if (player == null) return;
    final target = (player.currentPosition + deltaMs).clamp(0, player.duration < 0 ? 0 : player.duration);
    player.seekTo(target);
  }

  void _scheduleAutoHide() {
    _controlsHideTimer?.cancel();
    if (_controlsVisible && !_subtitleMenuOpen && !_bitrateMenuOpen) {
      _controlsHideTimer = Timer(const Duration(milliseconds: _controlsHideDelayMs), () {
        if (mounted) setState(() => _controlsVisible = false);
        _screenFocusNode.requestFocus();
      });
    }
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    // See the matching comment in initState — PlayerControlsBar remounts
    // fresh here, and _screenFocusNode still holds focus at that instant,
    // so autofocus alone won't claim it. Request explicitly instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _playPauseFocusNode.requestFocus();
    });
    _scheduleAutoHide();
  }

  // Passive "was any key pressed" signal (HomeScreen uses the same
  // HardwareKeyboard.addHandler pattern for its own debounce timing) —
  // resets the controls auto-hide countdown on any interaction while
  // controls are visible, matching Kotlin's `interactionTick` counter.
  // Never consumes: Flutter's bubbling key dispatch means a focused
  // button already got first crack at the event through its own
  // onKeyEvent; this only observes.
  bool _recordInteraction(KeyEvent event) {
    if (event is KeyDownEvent && _controlsVisible && !_subtitleMenuOpen && !_bitrateMenuOpen) {
      _scheduleAutoHide();
    }
    return false;
  }

  KeyEventResult _handleScreenKeyEvent(FocusNode node, KeyEvent event) {
    if (_subtitleMenuOpen || _bitrateMenuOpen) return KeyEventResult.ignored;

    if (event is KeyUpEvent) {
      if (_heldKey == event.logicalKey) {
        _heldKey = null;
        _heldRepeatCount = 0;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isFresh = _heldKey != key;
    if (isFresh) {
      _heldKey = key;
      _heldRepeatCount = 0;
    } else {
      _heldRepeatCount++;
    }

    if (_controlsVisible) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final direction = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      _seekBy(direction * seekIncrementForHold(_heldRepeatCount));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (isFresh) {
        _togglePlayPause();
        _showControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      if (isFresh) {
        _showControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handleBack() async {
    final controller = _controller;
    final duration = widget.detail.duration ?? controller?.value.duration.inMilliseconds ?? 0;
    final position = controller?.value.position.inMilliseconds ?? 0;
    _sync?.stop();
    await _reporter.report(widget.detail.ratingKey, 'stopped', position, duration);
    widget.onExit();
  }

  void _onSelectSubtitle(SubtitleOption option) {
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() {
      _subtitleStreamId = option.streamId;
      _subtitleMenuOpen = false;
    });
    _applyDecisionChange(restartPositionMs: restartPositionMs);
    _screenFocusNode.requestFocus();
  }

  void _onSelectBitrate(int kbps) {
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() {
      _maxVideoBitrateKbps = kbps;
      _bitrateMenuOpen = false;
    });
    widget.onBitrateChanged(kbps);
    _applyDecisionChange(restartPositionMs: restartPositionMs);
    _screenFocusNode.requestFocus();
  }

  void _applyDecisionChange({required int restartPositionMs}) {
    final newDecision = decidePlayback(widget.detail, _subtitleStreamId, forceBurn: widget.settings.forceBurnSubtitles);
    final newIdentity = _identityFor(newDecision, _maxVideoBitrateKbps);
    _decision = newDecision;

    if (newIdentity == _playerIdentity) {
      final controller = _controller;
      if (controller != null) unawaited(_attachCaptions(controller));
      return;
    }

    _playerIdentity = newIdentity;
    _phaseSub?.cancel();
    _waitingOnSub?.cancel();
    _sync?.stop();
    final oldController = _controller;
    oldController?.removeListener(_handleControllerTick);
    setState(() {
      _controller = null;
      _player = null;
      _sync = null;
    });
    unawaited(oldController?.dispose());
    unawaited(_initPlayer(startPositionMs: restartPositionMs));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final subtitlesAvailable = _subtitleOptions.length > 1; // more than just "Off"

    return BackHandler(
      onBack: () => unawaited(_handleBack()),
      child: Focus(
        focusNode: _screenFocusNode,
        onKeyEvent: _handleScreenKeyEvent,
        child: ColoredBox(
          color: AppColors.scrim,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null && controller.value.isInitialized)
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              if (_isBuffering) const Center(child: AppLoadingIndicator()),
              if (_controlsVisible)
                Positioned(
                  left: 24,
                  top: 24,
                  child: _Chip(child: AppText(widget.detail.title, color: AppColors.white)),
                ),
              if (widget.relay != null && _connectionState != ConnectionState.connected && _controlsVisible)
                Positioned(
                  right: 24,
                  top: 24,
                  child: _Chip(child: AppText(_syncStatusLabel(), color: AppColors.white)),
                ),
              if (_phase == PlaybackPhase.waitingForPeers && _waitingOn.isNotEmpty)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(child: _Chip(child: const AppText('Waiting for the room to catch up…', color: AppColors.white))),
                ),
              if (widget.settings.showChatOverlay && _sync != null)
                Align(
                  alignment: _chatAlignment(),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ChatOverlay(messages: _sync!.chatMessages, corner: widget.settings.chatOverlayCorner),
                  ),
                ),
              if (_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PlayerControlsBar(
                    isPlaying: _isPlaying,
                    positionMs: _positionMs,
                    durationMs: _durationMs,
                    bufferedFraction: _bufferedFraction,
                    subtitlesAvailable: subtitlesAvailable,
                    playPauseFocusNode: _playPauseFocusNode,
                    onPlayPause: _togglePlayPause,
                    onRewind: () => _seekBy(-_skipIncrementMs),
                    onForward: () => _seekBy(_skipIncrementMs),
                    onOpenSubtitles: () => setState(() {
                      _controlsVisible = false;
                      _subtitleMenuOpen = true;
                    }),
                    onOpenBitrate: () => setState(() {
                      _controlsVisible = false;
                      _bitrateMenuOpen = true;
                    }),
                    chatAvailable: _chatUrl != null,
                    onOpenChatQr: () => setState(() => _chatQrOpen = true),
                  ),
                ),
              if (_subtitleMenuOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SubtitleMenu(
                      options: _subtitleOptions,
                      selectedStreamId: _subtitleStreamId,
                      onSelect: _onSelectSubtitle,
                      onDismiss: () {
                        setState(() => _subtitleMenuOpen = false);
                        _screenFocusNode.requestFocus();
                      },
                    ),
                  ),
                ),
              if (_bitrateMenuOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: BitrateMenu(
                      selectedKbps: _maxVideoBitrateKbps,
                      onSelect: _onSelectBitrate,
                      onDismiss: () {
                        setState(() => _bitrateMenuOpen = false);
                        _screenFocusNode.requestFocus();
                      },
                    ),
                  ),
                ),
              if (_chatQrOpen && _chatUrl != null)
                Positioned(
                  right: 24,
                  top: 24,
                  child: ChatQrOverlay(chatUrl: _chatUrl!, onDismiss: () => setState(() => _chatQrOpen = false)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Alignment _chatAlignment() => switch (widget.settings.chatOverlayCorner) {
        ChatOverlayCorner.topStart => Alignment.topLeft,
        ChatOverlayCorner.topEnd => Alignment.topRight,
        ChatOverlayCorner.bottomStart => Alignment.bottomLeft,
        ChatOverlayCorner.bottomEnd => Alignment.bottomRight,
      };

  String _syncStatusLabel() => switch (_connectionState) {
        ConnectionState.connecting => 'Sync: connecting…',
        ConnectionState.reconnecting => 'Sync: reconnecting…',
        ConnectionState.roomFull => 'Sync: room full',
        _ => 'Sync: off',
      };
}

class _Chip extends StatelessWidget {
  final Widget child;

  const _Chip({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.scrim.withValues(alpha: 0.6)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: child),
    );
  }
}
