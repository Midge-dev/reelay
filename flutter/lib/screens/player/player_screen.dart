import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../data/plex/media_facts.dart';
import '../../data/plex/plex_http_client.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_server_api.dart';
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
import '../../sync/room_roster.dart';
import '../../sync/sync_view_model.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/app_loading_indicator.dart';
import '../common/artwork.dart';
import '../common/chat_overlay.dart';
import 'chat_qr_overlay.dart';
import 'player_controls_bar.dart';
import 'player_menu_panel.dart';
import 'up_next_card.dart';

const _reportIntervalMs = 5000;
const _controlsHideDelayMs = 3000;
const _skipIncrementMs = 10000;
const _controlsFadeDuration = Duration(milliseconds: 200);

/// Playback, solo or in a Watch Together room. `video_player` has no
/// play/pause reason codes and no seek-discontinuity event — both handled
/// in [VideoPlayerSyncedPlayer] — and no API for selecting a subtitle
/// track muxed into the video container, so [subtitleOptions]
/// marks every embedded track as burn-required — selecting one forces a
/// transcode with the subtitles baked in, rather than direct-playing.
///
/// A bitrate change recreates the whole player, while a subtitle-only
/// change while direct-playing reuses it ([_identityFor]): `video_player`
/// has no media-source-swap API at all (a new HLS bitrate means a new URL means a
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

  /// The stream wouldn't open or errored mid-play: a plain one-sentence
  /// reason for screen 25, and where to pick up again.
  final void Function(String reason, int positionMs) onFailed;
  // Screen 16 — both null when playing a movie or when the show context
  // isn't available (see Player.showRatingKey's doc comment).
  final Future<PlexOnDeckItem?> Function()? loadNextEpisode;
  final ValueChanged<PlexOnDeckItem>? onPlayNext;

  /// Who this television is in a Watch Together room (its presence).
  final String localName;
  final String? localAvatarUrl;

  const PlayerScreen({
    super.key,
    required this.server,
    required this.detail,
    required this.clientIdentifier,
    this.relay,
    required this.settings,
    required this.onBitrateChanged,
    required this.onExit,
    required this.onFailed,
    this.loadNextEpisode,
    this.onPlayNext,
    this.localName = 'You',
    this.localAvatarUrl,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final TimelineReporter _reporter;

  /// One per playback, kept across subtitle/bitrate restarts: the stream
  /// request and every timeline report carry it (see TimelineReporter).
  final _sessionIdentifier = const Uuid().v4();
  late final Dio _captionClient;

  late PlexPart? _resolvedPart;
  bool _failed = false;
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
  RoomRoster? _roster;
  StreamSubscription<List<RoomPerson>>? _rosterSub;
  List<RoomPerson> _people = const [];
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
    return relayUrlToChatUrl(
      relay.relayUrl,
      roomId,
      '',
      themeId: AppColors.currentTheme.name,
    );
  }

  @override
  void initState() {
    super.initState();
    _reporter = TimelineReporter(
      widget.server,
      widget.clientIdentifier,
      _sessionIdentifier,
    );
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

    _subtitleStreamId = firstSubtitleStreamId(widget.detail);

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
      final roster = RoomRoster(
        relay: widget.relay!,
        localName: widget.localName,
        localAvatarUrl: widget.localAvatarUrl,
      )..start();
      _roster = roster;
      _rosterSub = roster.people.listen(
        (people) => setState(() => _people = people),
      );
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
    _rosterSub?.cancel();
    _roster?.dispose();
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
    await _selectBurnSubtitle();
    if (!mounted || generation != _playerGeneration) return;
    final url = PlexPlayerFactory.mediaUrl(
      widget.server,
      _decision,
      _maxVideoBitrateKbps,
      clientIdentifier: widget.clientIdentifier,
      sessionIdentifier: _sessionIdentifier,
      offsetMs: startPositionMs,
    );
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
    } catch (_) {
      unawaited(controller.dispose());
      if (mounted && generation == _playerGeneration) {
        _fail(
          '${widget.server.name} sent a stream this TV couldn\'t open',
          startPositionMs,
        );
      }
      return;
    }
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

  /// A burn-in transcode paints whatever subtitle the part has selected on
  /// the server, so select ours first (see subtitleSelectionUrl). Best
  /// effort: if the server refuses, the transcode still starts and may burn
  /// its stored choice — there's no direct-play fallback, since
  /// video_player can't show an embedded track itself.
  Future<void> _selectBurnSubtitle() async {
    final decision = _decision;
    final part = _resolvedPart;
    final streamId = decision is Transcode ? decision.subtitleStreamId : null;
    if (part == null || streamId == null) return;
    try {
      await PlexServerApi(
        widget.server,
        widget.clientIdentifier,
      ).selectSubtitleStream(part.id, streamId);
    } catch (_) {
      // See above: start the transcode regardless.
    }
  }

  Future<void> _attachCaptions(VideoPlayerController controller) async {
    final part = _resolvedPart;
    if (part == null) {
      await controller.setClosedCaptionFile(null);
      return;
    }
    final source = resolveSubtitleSource(part, _subtitleStreamId);
    if (source is ExternalSubtitle) {
      try {
        await controller.setClosedCaptionFile(_fetchCaptionFile(source));
      } catch (_) {
        // A subtitle file that won't download isn't worth stopping the
        // film for — play on without it.
        await controller.setClosedCaptionFile(null);
      }
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
    if (value.hasError) {
      _fail(
        'The stream from ${widget.server.name} stopped partway through',
        _positionMs > 0 ? _positionMs : widget.detail.viewOffset ?? 0,
      );
      return;
    }
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
          if (!mounted) return;
          setState(() => _controlsVisible = false);
          // Never pull focus out of an open panel: focus decides which Back
          // handler answers, and with it on the screen node Back left the
          // player instead of closing the menu.
          if (_menuOpen || _chatQrOpen) return;
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
  // controls are visible.
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
    // Keys from inside an open panel bubble up here too; with the controls
    // hidden, Up/Down would summon them and take focus out of the panel.
    if (_menuOpen || _chatQrOpen) return KeyEventResult.ignored;

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

  /// Once only: a dying controller can report its error on several ticks.
  void _fail(String reason, int positionMs) {
    if (_failed) return;
    _failed = true;
    _controller?.removeListener(_handleControllerTick);
    _sync?.stop();
    final duration = widget.detail.duration ?? _durationMs;
    unawaited(
      _reporter.report(widget.detail.ratingKey, 'stopped', positionMs, duration),
    );
    widget.onFailed(reason, positionMs);
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
    return option?.label ?? 'Off';
  }

  /// "THE LONG FIELD · S2 E4" for an episode, the year for a movie.
  String? get _kicker {
    final d = widget.detail;
    final show = d.grandparentTitle;
    if (show != null) {
      final se = [
        if (d.parentIndex != null) 'S${d.parentIndex}',
        if (d.index != null) 'E${d.index}',
      ].join(' ');
      return [show.toUpperCase(), if (se.isNotEmpty) se].join(' · ');
    }
    return d.year?.toString();
  }

  /// Screen 13's top-right chips: how it is being played, then what.
  List<String> get _infoChips {
    final media = widget.detail.media.firstOrNull;
    final facts = media == null ? null : MediaFacts(media);
    return [
      _decision is DirectPlay ? 'Direct play' : 'Transcoding',
      ?facts?.picture,
      ?facts?.audio,
    ];
  }

  String get _currentBitrateLabel {
    final preset = AppSettings.bitratePresets.firstWhereOrNull(
      (p) => p.kbps == _maxVideoBitrateKbps,
    );
    // "20 Mbps (High)" -> "20 Mbps": the pill states the value, not its tier.
    return preset?.label.split(' (').first ??
        '${_maxVideoBitrateKbps ~/ 1000} Mbps';
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
          color: AppColors.videoMatte,
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
                // Screen 15: the one moment Watch Together is allowed to be
                // loud — the reason the room paused takes the centre.
                Center(
                  child: _RoomPausedCard(
                    who: waitingOnPhrase(
                      _waitingOn,
                      (id) => _roster?.nameOf(id),
                    ),
                    count: _waitingOn.length,
                  ),
                ),
              if (widget.settings.showChatOverlay && _sync != null)
                Align(
                  alignment: _chatAlignment(),
                  child: Padding(
                    padding: EdgeInsets.all(24.du(context)),
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
                              kicker: _kicker,
                              title: widget.detail.title,
                              // In a room the top-right belongs to the
                              // room (screen 15), not to how it's playing.
                              chips: widget.relay != null
                                  ? const []
                                  : _infoChips,
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
                              subtitleLabel: _currentSubtitleLabel,
                              qualityLabel: _currentBitrateLabel,
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
                              inRoom: widget.relay != null,
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
              // Screen 15: who's here and whether the room is together —
              // permanent while in a room, not part of the fading controls.
              if (widget.relay != null && !_chatQrOpen)
                Positioned(
                  right: 64.du(context),
                  top: 56.du(context),
                  child: _RoomStrip(
                    people: [
                      for (final p in _people) (p.name, p.avatarUrl),
                      (widget.localName, widget.localAvatarUrl),
                    ],
                    status: _roomStatus(),
                  ),
                ),
              if (_chatQrOpen && _chatUrl != null)
                Positioned(
                  right: 24.du(context),
                  top: 24.du(context),
                  child: ChatQrOverlay(
                    chatUrl: _chatUrl!,
                    onDismiss: () => setState(() => _chatQrOpen = false),
                  ),
                ),
              if (_upNextItem != null && !_menuOpen)
                Positioned(
                  right: 64.du(context),
                  bottom: 44.du(context),
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
                    // Back to the controls with the menu button focused —
                    // they may have auto-hidden while the panel was open.
                    setState(() {
                      _menuOpen = false;
                      _controlsVisible = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _menuFocusNode.requestFocus();
                    });
                    _scheduleAutoHide();
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

  (String, Color) _roomStatus() {
    if (_connectionState != ConnectionState.connected) {
      return (_syncStatusLabel(), AppColors.warning);
    }
    if (_phase == PlaybackPhase.waitingForPeers && _waitingOn.isNotEmpty) {
      return (
        'Holding for ${waitingOnPhrase(_waitingOn, (id) => _roster?.nameOf(id))}',
        AppColors.warning,
      );
    }
    return ('In sync', AppColors.success);
  }

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
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14.du(context),
          vertical: 8.du(context),
        ),
        child: child,
      ),
    );
  }
}

/// Screen 13's header: a top scrim with the show/episode kicker and title
/// on the left and how it is playing (direct or transcoded, picture,
/// audio) as chips on the right. The subtitle and quality values now live
/// on their own pills in [PlayerControlsBar].
class _TitleBar extends StatelessWidget {
  final String? kicker;
  final String title;
  final List<String> chips;

  const _TitleBar({this.kicker, required this.title, required this.chips});

  @override
  Widget build(BuildContext context) {
    final kicker = this.kicker;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        64.du(context),
        56.du(context),
        64.du(context),
        72.du(context),
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.linear(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.canvas.withValues(alpha: 0.9),
            AppColors.canvas.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null) ...[
                  AppText(
                    kicker,
                    style: AppTypography.micro,
                    color: AppColors.ink2,
                  ),
                  SizedBox(height: 8.du(context)),
                ],
                AppText(
                  title,
                  style: AppTypography.title1.copyWith(fontSize: 40),
                  color: AppColors.inkOnArt,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          SizedBox(width: 24.du(context)),
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) SizedBox(width: 10.du(context)),
            _Chip(
              child: AppText(
                chip,
                style: AppTypography.caption,
                color: AppColors.inkOnArt,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomPausedCard extends StatelessWidget {
  /// "Marcus", "Marcus and Sam", "3 people".
  final String who;
  final int count;

  const _RoomPausedCard({required this.who, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 48.du(context),
        vertical: 36.du(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.86),
        border: Border.all(color: AppColors.lineStrong, width: 1.du(context)),
        borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
        boxShadow: AppElevation.overlay,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10.du(context),
                height: 10.du(context),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(width: 14.du(context)),
              AppText(
                'PAUSED FOR THE ROOM',
                style: AppTypography.micro,
                color: AppColors.warning,
              ),
            ],
          ),
          SizedBox(height: 14.du(context)),
          AppText(
            '$who ${count == 1 ? 'is' : 'are'} buffering',
            style: AppTypography.title2.copyWith(fontSize: 34),
            color: AppColors.inkOnArt,
          ),
          SizedBox(height: 14.du(context)),
          AppText(
            'Everyone resumes together',
            style: AppTypography.label,
            color: AppColors.ink2,
          ),
        ],
      ),
    );
  }
}

/// Screen 15's top-right: the room's faces, overlapping, and one line on
/// whether it is together, on the chip scrim.
class _RoomStrip extends StatelessWidget {
  final List<(String, String?)> people;
  final (String, Color) status;

  const _RoomStrip({required this.people, required this.status});

  static const _face = 44.0;
  static const _overlap = 14.0;
  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final (label, dot) = status;
    final shown = people.take(_shown).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: (_face + (shown.length - 1) * (_face - _overlap)).du(context),
          height: _face.du(context),
          child: Stack(
            children: [
              for (final (i, (name, avatar)) in shown.indexed)
                Positioned(
                  left: (i * (_face - _overlap)).du(context),
                  child: _Face(name: name, avatarUrl: avatar),
                ),
            ],
          ),
        ),
        SizedBox(width: 14.du(context)),
        _Chip(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.du(context),
                height: 8.du(context),
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              SizedBox(width: 10.du(context)),
              AppText(
                label,
                style: AppTypography.caption,
                color: AppColors.inkOnArt,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  final String name;
  final String? avatarUrl;

  const _Face({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return Container(
      width: _RoomStrip._face.du(context),
      height: _RoomStrip._face.du(context),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceOverlay,
        border: Border.all(color: AppColors.canvas, width: 2.du(context)),
      ),
      child: ClipOval(
        child: url != null && url.isNotEmpty
            ? Artwork(imageUrl: url)
            : Center(
                child: AppText(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTypography.caption,
                  color: AppColors.ink2,
                ),
              ),
      ),
    );
  }
}
