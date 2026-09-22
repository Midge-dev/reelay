import 'dart:async';

import 'package:collection/collection.dart';
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
import '../../theme/typography.dart';
import '../common/app_loading_indicator.dart';
import '../common/chat_overlay.dart';
import 'chat_qr_overlay.dart';
import 'player_controls_bar.dart';
import 'player_menu_panel.dart';
import 'up_next_card.dart';

const _reportIntervalMs = 5000;
const _controlsHideDelayMs = 3000;
const _skipIncrementMs = 10000;
const _controlsFadeDuration = Duration(milliseconds: 200);

/// Ports ui/player/PlayerScreen.kt — the biggest platform-boundary piece of
/// this conversion. See project_flutter_full_conversion.md for the two
/// spiked risks this resolved (no play/pause reason codes, no seek-
/// discontinuity event — both handled fine by [VideoPlayerSyncedPlayer]).
/// Unlike Kotlin/ExoPlayer, this player has no API for selecting a
/// subtitle track muxed into the video container, so [subtitleOptions]
/// marks every embedded track as burn-required — selecting one forces a
/// transcode with the subtitles baked in, rather than direct-playing.
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
  // Screen 16 — both null when playing a movie or when the show context
  // isn't available (see Player.showRatingKey's doc comment).
  final Future<PlexOnDeckItem?> Function()? loadNextEpisode;
  final ValueChanged<PlexOnDeckItem>? onPlayNext;

  const PlayerScreen({
    super.key,
    required this.server,
    required this.detail,
    required this.clientIdentifier,
    this.relay,
    required this.settings,
    required this.onBitrateChanged,
    required this.onExit,
    this.loadNextEpisode,
    this.onPlayNext,
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
  bool _chatQrOpen = false;

  int _positionMs = 0;
  int _durationMs = 0;
  double _bufferedFraction = 0;

  // Screen 16 — appears 40s before the end; dismissing it ("Not now")
  // holds for the rest of this episode, so _upNextDismissed (not just
  // clearing _upNextItem) is what actually suppresses it, since the
  // trigger check would otherwise re-show it the very next tick.
  static const _upNextTriggerMs = 40000;
  PlexOnDeckItem? _upNextItem;
  bool _upNextLoadAttempted = false;
  bool _upNextDismissed = false;

  Timer? _controlsHideTimer;
  Timer? _reportTimer;

  final _screenFocusNode = FocusNode(debugLabel: 'player-screen');
  final _progressFocusNode = FocusNode(debugLabel: 'player-progress');
  final _rewindFocusNode = FocusNode(debugLabel: 'player-rewind');
  final _playPauseFocusNode = FocusNode(debugLabel: 'player-play-pause');
  final _forwardFocusNode = FocusNode(debugLabel: 'player-forward');
  final _subtitlesFocusNode = FocusNode(debugLabel: 'player-subtitles');
  final _bitrateFocusNode = FocusNode(debugLabel: 'player-bitrate');
  final _chatFocusNode = FocusNode(debugLabel: 'player-chat');
  final _menuFocusNode = FocusNode(debugLabel: 'player-menu');
  bool _menuOpen = false;

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

    final media = widget.detail.media.isNotEmpty
        ? widget.detail.media.first
        : null;
    _resolvedPart = media != null && media.parts.isNotEmpty
        ? media.parts.first
        : null;
    _subtitleOptions = _resolvedPart != null
        ? subtitleOptions(_resolvedPart!)
        : const [];

    final defaultId = defaultSubtitleStreamId(widget.detail);
    final defaultOption = _subtitleOptions.firstWhereOrNull(
      (o) => o.streamId == defaultId,
    );
    // Only auto-select Plex's remembered subtitle if it doesn't force a
    // transcode: embedded tracks are offered in the CC menu (see
    // subtitleOptions) but a burn-required transcode should be something
    // the user opts into there, not something that silently kicks off on
    // first play just because Plex remembered a language preference.
    _subtitleStreamId = (defaultOption != null && !defaultOption.requiresBurn)
        ? defaultId
        : null;

    _maxVideoBitrateKbps = widget.settings.maxVideoBitrateKbps;
    _decision = decidePlayback(
      widget.detail,
      _subtitleStreamId,
      forceBurn: widget.settings.forceBurnSubtitles,
    );
    _playerIdentity = _identityFor(_decision, _maxVideoBitrateKbps);

    HardwareKeyboard.instance.addHandler(_recordInteraction);
    _reportTimer = Timer.periodic(
      const Duration(milliseconds: _reportIntervalMs),
      (_) => _reportProgress(),
    );
    _scheduleAutoHide();
    // Explicit, not autofocus: PlayerControlsBar stays mounted continuously
    // (see build() — its visibility is an AnimatedOpacity fade, not a
    // conditional-existence swap) specifically so ExcludeFocus/IgnorePointer
    // toggling and the fade animation both have a stable widget to act on.
    // Autofocus only fires on a widget's first build, so on a widget that's
    // already built once it silently no-ops, leaving every subsequent D-pad
    // press swallowed by the screen-level handler with the controls stuck
    // visible but unnavigable — hence the explicit requestFocus() here and
    // in _showControls().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPauseFocusNode.requestFocus();
    });

    unawaited(_initPlayer(startPositionMs: widget.detail.viewOffset ?? 0));

    if (widget.relay != null) {
      _connectionSub = widget.relay!.connectionState.listen(
        (state) => setState(() => _connectionState = state),
      );
      _roomIdSub = widget.relay!.roomId.listen(
        (id) => setState(() => _roomId = id),
      );
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
    _progressFocusNode.dispose();
    _rewindFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _forwardFocusNode.dispose();
    _subtitlesFocusNode.dispose();
    _bitrateFocusNode.dispose();
    _chatFocusNode.dispose();
    _menuFocusNode.dispose();
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
    final url = PlexPlayerFactory.mediaUrl(
      widget.server,
      _decision,
      _maxVideoBitrateKbps,
      offsetMs: startPositionMs,
    );
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await controller.initialize();
    if (!mounted || generation != _playerGeneration) {
      unawaited(controller.dispose());
      return;
    }
    // Transcode already starts the stream at startPositionMs via the url's
    // offset (see PlexPlayerFactory.transcodeUrl) — seeking again here would
    // target a position the transcode session never produced. Direct play
    // serves the whole original file, so it still needs the explicit seek.
    if (startPositionMs > 0 && _decision is DirectPlay) {
      await controller.seekTo(Duration(milliseconds: startPositionMs));
    }
    await _attachCaptions(controller);
    controller.addListener(_handleControllerTick);

    final player = VideoPlayerSyncedPlayer(controller);
    final sync = SyncViewModel(player: player, relay: widget.relay);

    _phaseSub?.cancel();
    _waitingOnSub?.cancel();
    _phaseSub = sync.phase.listen((phase) => setState(() => _phase = phase));
    _waitingOnSub = sync.waitingOn.listen(
      (waitingOn) => setState(() => _waitingOn = waitingOn),
    );

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
    final url =
        '${widget.server.baseUrl}${source.key}?X-Plex-Token=${widget.server.accessToken}';
    final response = await _captionClient.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final content = response.data ?? '';
    return content.trimLeft().startsWith('WEBVTT')
        ? WebVTTCaptionFile(content)
        : SubRipCaptionFile(content);
  }

  void _handleControllerTick() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    final buffered = value.buffered;
    final bufferedMs = buffered.isEmpty
        ? 0
        : buffered
              .map((r) => r.end.inMilliseconds)
              .reduce((a, b) => a > b ? a : b);
    setState(() {
      _isPlaying = value.isPlaying;
      _isBuffering = value.isBuffering;
      _positionMs = value.position.inMilliseconds;
      _durationMs = value.duration.inMilliseconds;
      _bufferedFraction = _durationMs > 0
          ? (bufferedMs / _durationMs).clamp(0.0, 1.0)
          : 0.0;
    });
    _maybeLoadUpNext();
  }

  void _maybeLoadUpNext() {
    if (_upNextDismissed || _upNextLoadAttempted) return;
    final loadNextEpisode = widget.loadNextEpisode;
    if (loadNextEpisode == null) return;
    if (_durationMs <= 0 || _durationMs - _positionMs > _upNextTriggerMs)
      return;
    _upNextLoadAttempted = true;
    loadNextEpisode().then((item) {
      if (mounted && item != null) setState(() => _upNextItem = item);
    });
  }

  void _dismissUpNext() => setState(() {
    _upNextItem = null;
    _upNextDismissed = true;
  });

  void _playUpNext() {
    final item = _upNextItem;
    if (item == null) return;
    widget.onPlayNext?.call(item);
  }

  Future<void> _reportProgress() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.value.isPlaying ? 'playing' : 'paused';
    final duration =
        widget.detail.duration ?? controller.value.duration.inMilliseconds;
    await _reporter.report(
      widget.detail.ratingKey,
      state,
      controller.value.position.inMilliseconds,
      duration,
    );
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
    final target = (player.currentPosition + deltaMs).clamp(
      0,
      player.duration < 0 ? 0 : player.duration,
    );
    player.seekTo(target);
  }

  void _scheduleAutoHide() {
    _controlsHideTimer?.cancel();
    if (_controlsVisible) {
      _controlsHideTimer = Timer(
        const Duration(milliseconds: _controlsHideDelayMs),
        () {
          if (mounted) setState(() => _controlsVisible = false);
          _screenFocusNode.requestFocus();
        },
      );
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
    if (_isKeyActive(event) && _controlsVisible) {
      _scheduleAutoHide();
    }
    return false;
  }

  // A held D-pad key arrives as one KeyDownEvent followed by a stream of
  // KeyRepeatEvents (a third, distinct KeyEvent subtype — not more
  // KeyDownEvents) until the eventual KeyUpEvent. Treating only
  // KeyDownEvent as "key active" — the mistake here originally — silently
  // drops every repeat, so held-key repeat counts never advance past 0 and
  // hold-to-accelerate never actually accelerates.
  bool _isKeyActive(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  // Shared by the hidden-controls screen-level shortcut below and the
  // focused-progress-track handler ([_handleProgressSeekKey]) — a D-pad
  // hold accelerates the seek jump the longer it's held (see
  // seekIncrementForHold), keyed off repeats of the *same* logical key
  // since the last KeyUp. The two call sites are mutually exclusive
  // (one requires controls hidden, the other requires the progress track
  // focused, which only exists while controls are visible) so sharing
  // this bookkeeping is safe, not just DRY.
  int _trackHeldRepeat(LogicalKeyboardKey key) {
    if (_heldKey != key) {
      _heldKey = key;
      _heldRepeatCount = 0;
    } else {
      _heldRepeatCount++;
    }
    return _heldRepeatCount;
  }

  void _trackKeyUp(LogicalKeyboardKey key) {
    if (_heldKey == key) {
      _heldKey = null;
      _heldRepeatCount = 0;
    }
  }

  KeyEventResult _handleProgressSeekKey(KeyEvent event) {
    if (!_isKeyActive(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight)
      return KeyEventResult.ignored;
    final direction = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
    _seekBy(direction * seekIncrementForHold(_trackHeldRepeat(key)));
    return KeyEventResult.handled;
  }

  KeyEventResult _handleScreenKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      _trackKeyUp(event.logicalKey);
      return KeyEventResult.ignored;
    }
    if (!_isKeyActive(event)) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final repeatCount = _trackHeldRepeat(key);
    final isFresh = repeatCount == 0;

    if (_controlsVisible) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final direction = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      _seekBy(direction * seekIncrementForHold(repeatCount));
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
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
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
    final duration =
        widget.detail.duration ??
        controller?.value.duration.inMilliseconds ??
        0;
    final position = controller?.value.position.inMilliseconds ?? 0;
    _sync?.stop();
    await _reporter.report(
      widget.detail.ratingKey,
      'stopped',
      position,
      duration,
    );
    widget.onExit();
  }

  void _cycleSubtitle() {
    final options = _subtitleOptions;
    final currentIndex = options.indexWhere(
      (o) => o.streamId == _subtitleStreamId,
    );
    final next = options[(currentIndex + 1) % options.length];
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() => _subtitleStreamId = next.streamId);
    _applyDecisionChange(restartPositionMs: restartPositionMs);
  }

  void _cycleBitrate() {
    final presets = AppSettings.bitratePresets;
    final currentIndex = presets.indexWhere(
      (p) => p.kbps == _maxVideoBitrateKbps,
    );
    final next = presets[(currentIndex + 1) % presets.length];
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() => _maxVideoBitrateKbps = next.kbps);
    widget.onBitrateChanged(next.kbps);
    _applyDecisionChange(restartPositionMs: restartPositionMs);
  }

  // Same effect as _cycleSubtitle/_cycleBitrate above, but jumping straight
  // to a chosen option rather than stepping to the next one — what the
  // Player menu panel (screen 14) needs, the button-row cycle shortcuts
  // don't.
  void _selectSubtitle(int? streamId) {
    if (streamId == _subtitleStreamId) return;
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() => _subtitleStreamId = streamId);
    _applyDecisionChange(restartPositionMs: restartPositionMs);
  }

  void _selectBitrate(int kbps) {
    if (kbps == _maxVideoBitrateKbps) return;
    final restartPositionMs = _player?.currentPosition ?? 0;
    setState(() => _maxVideoBitrateKbps = kbps);
    widget.onBitrateChanged(kbps);
    _applyDecisionChange(restartPositionMs: restartPositionMs);
  }

  String get _currentSubtitleLabel {
    final options = _subtitleOptions;
    final option = options.firstWhereOrNull(
      (o) => o.streamId == _subtitleStreamId,
    );
    return 'CC: ${option?.label ?? 'Off'}';
  }

  String get _currentBitrateLabel {
    final preset = AppSettings.bitratePresets.firstWhereOrNull(
      (p) => p.kbps == _maxVideoBitrateKbps,
    );
    return preset?.label ?? '${_maxVideoBitrateKbps ~/ 1000} Mbps';
  }

  void _applyDecisionChange({required int restartPositionMs}) {
    final newDecision = decidePlayback(
      widget.detail,
      _subtitleStreamId,
      forceBurn: widget.settings.forceBurnSubtitles,
    );
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
    final subtitlesAvailable =
        _subtitleOptions.length > 1; // more than just "Off"

    return BackHandler(
      onBack: () => unawaited(_handleBack()),
      child: Focus(
        focusNode: _screenFocusNode,
        onKeyEvent: _handleScreenKeyEvent,
        child: ColoredBox(
          color: AppScrims.dialog,
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
              if (_phase == PlaybackPhase.waitingForPeers &&
                  _waitingOn.isNotEmpty)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _Chip(
                      child: AppText(
                        'Waiting for the room to catch up…',
                        color: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                ),
              if (widget.settings.showChatOverlay && _sync != null)
                Align(
                  alignment: _chatAlignment(),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ChatOverlay(
                      messages: _sync!.chatMessages,
                      corner: widget.settings.chatOverlayCorner,
                    ),
                  ),
                ),
              // Kept mounted continuously (unlike the menus/overlays above,
              // which still use conditional existence) so its visibility can
              // be an AnimatedOpacity fade rather than an instant swap —
              // IgnorePointer/ExcludeFocus keep it inert while faded out.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: ExcludeFocus(
                    excluding: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: _controlsFadeDuration,
                      curve: Curves.easeInOut,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: _TitleBar(
                              title: widget.detail.title,
                              subtitleLabel: _currentSubtitleLabel,
                              qualityLabel: _currentBitrateLabel,
                            ),
                          ),
                          if (widget.relay != null &&
                              _connectionState != ConnectionState.connected)
                            Positioned(
                              right: 24,
                              top: 24,
                              child: _Chip(
                                child: AppText(
                                  _syncStatusLabel(),
                                  color: AppColors.inkOnArt,
                                ),
                              ),
                            ),
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
                              progressFocusNode: _progressFocusNode,
                              rewindFocusNode: _rewindFocusNode,
                              playPauseFocusNode: _playPauseFocusNode,
                              forwardFocusNode: _forwardFocusNode,
                              subtitlesFocusNode: _subtitlesFocusNode,
                              bitrateFocusNode: _bitrateFocusNode,
                              chatFocusNode: _chatFocusNode,
                              onPlayPause: _togglePlayPause,
                              onRewind: () => _seekBy(-_skipIncrementMs),
                              onForward: () => _seekBy(_skipIncrementMs),
                              onSeekKeyEvent: _handleProgressSeekKey,
                              onCycleSubtitles: _cycleSubtitle,
                              onCycleBitrate: _cycleBitrate,
                              chatAvailable: _chatUrl != null,
                              onOpenChatQr: () =>
                                  setState(() => _chatQrOpen = true),
                              menuFocusNode: _menuFocusNode,
                              onOpenMenu: () =>
                                  setState(() => _menuOpen = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_chatQrOpen && _chatUrl != null)
                Positioned(
                  right: 24,
                  top: 24,
                  child: ChatQrOverlay(
                    chatUrl: _chatUrl!,
                    onDismiss: () => setState(() => _chatQrOpen = false),
                  ),
                ),
              if (_upNextItem != null && !_menuOpen)
                Positioned(
                  right: 64,
                  bottom: 64,
                  child: BackHandler(
                    onBack: _dismissUpNext,
                    child: UpNextCard(
                      server: widget.server,
                      item: _upNextItem!,
                      onPlayNow: _playUpNext,
                      onDismiss: _dismissUpNext,
                    ),
                  ),
                ),
              if (_menuOpen)
                PlayerMenuPanel(
                  subtitleOptions: _subtitleOptions,
                  selectedSubtitleStreamId: _subtitleStreamId,
                  onSelectSubtitle: _selectSubtitle,
                  selectedBitrateKbps: _maxVideoBitrateKbps,
                  onSelectBitrate: _selectBitrate,
                  onClose: () {
                    setState(() => _menuOpen = false);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _menuFocusNode.requestFocus();
                    });
                  },
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
      decoration: BoxDecoration(color: AppScrims.dialog.withValues(alpha: 0.6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }
}

/// A full-width header, mirroring [PlayerControlsBar]'s bottom scrim but
/// inverted — solid at the screen edge, fading to transparent toward the
/// video — instead of the small floating [_Chip] the title used to sit in.
/// Also carries the current CC/quality status, right-aligned: cycling
/// through either via its button in [PlayerControlsBar] (rather than
/// opening a picker menu) needs somewhere to show which option is active.
class _TitleBar extends StatelessWidget {
  final String title;
  final String subtitleLabel;
  final String qualityLabel;

  const _TitleBar({
    required this.title,
    required this.subtitleLabel,
    required this.qualityLabel,
  });

  @override
  Widget build(BuildContext context) {
    final statusStyle = AppTypography.body.copyWith(
      color: AppColors.inkOnArt.withValues(alpha: 0.75),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppScrims.dialog.withValues(alpha: 0.6),
            AppScrims.dialog.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: AppText(title, color: AppColors.inkOnArt)),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppText(qualityLabel, style: statusStyle),
              const SizedBox(height: 4),
              AppText(subtitleLabel, style: statusStyle),
            ],
          ),
        ],
      ),
    );
  }
}
