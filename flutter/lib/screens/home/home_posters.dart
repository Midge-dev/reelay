import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../focus/dpad_long_press.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/scroll_peek.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/remove_confirm_overlay.dart';
import '../common/time_format.dart';

const _typeEpisode = 'episode';

const _continueWatchingShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)));

/// Ports HomeScreen.kt's `recentlyAddedLabel`.
String recentlyAddedLabel(PlexLibraryItem item) {
  final parentTitle = item.parentTitle;
  if (item.type == 'season' && parentTitle != null) return parentTitle;
  return item.title;
}

/// Ports HomeScreen.kt's `continueWatchingLabel`.
String continueWatchingLabel(PlexOnDeckItem item) {
  if (item.type == _typeEpisode && item.grandparentTitle != null && item.parentIndex != null && item.index != null) {
    return '${item.grandparentTitle} · S${item.parentIndex}E${item.index}';
  }
  return item.title;
}

/// Ports HomeScreen.kt's `progressFraction`.
double progressFraction(PlexOnDeckItem item) {
  final duration = item.duration;
  if (duration == null || duration <= 0) return 0;
  final fraction = (item.viewOffset ?? 0) / duration;
  return fraction.clamp(0.0, 1.0);
}

/// Ports HomeScreen.kt's `WatchlistPoster` — a 2:3 poster with long-press-
/// to-remove. Reuses DpadLongPressDetector for the hold-to-open gesture;
/// the confirm overlay's own "swallow the trailing release" guard lives in
/// RemoveConfirmOverlay itself (see that file's doc comment for why).
class WatchlistPoster extends StatefulWidget {
  final PlexServer server;
  final PlexWatchlistItem entry;
  final VoidCallback onClick;
  final VoidCallback onRemove;
  final FocusNode? focusNode;
  final bool autofocus;
  final int staggerDelayMs;

  const WatchlistPoster({
    super.key,
    required this.server,
    required this.entry,
    required this.onClick,
    required this.onRemove,
    this.focusNode,
    this.autofocus = false,
    this.staggerDelayMs = 0,
  });

  @override
  State<WatchlistPoster> createState() => _WatchlistPosterState();
}

class _WatchlistPosterState extends State<WatchlistPoster> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _confirmingRemove = false;
  late final DpadLongPressDetector _longPress = DpadLongPressDetector(onLongPress: _openConfirm);

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'watchlist-poster');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    _longPress.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    if (_focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCardVisible(context);
      });
    }
  }

  void _openConfirm() => setState(() => _confirmingRemove = true);

  void _closeConfirm() {
    setState(() => _confirmingRemove = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      handleDpadSelect(event, longPress: _longPress, onClick: widget.onClick);

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      enabled: _confirmingRemove,
      onBack: _closeConfirm,
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    border: _focused ? Border.all(color: AppColors.accent, width: 2) : null,
                  ),
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    onKeyEvent: _handleKeyEvent,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _focusNode.requestFocus();
                        if (!_confirmingRemove) widget.onClick();
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Artwork(imageUrl: PlexImageUrl.of(widget.server, widget.entry.thumb), staggerDelayMs: widget.staggerDelayMs),
                          if (_confirmingRemove)
                            RemoveConfirmOverlay(
                              message: 'Remove ${widget.entry.title} from your watchlist?',
                              onConfirm: () {
                                setState(() => _confirmingRemove = false);
                                widget.onRemove();
                              },
                              onCancel: _closeConfirm,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppText(widget.entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ports HomeScreen.kt's `ContinueWatchingPoster` — a wider 16:9 card with
/// the same long-press-to-remove pattern as WatchlistPoster, plus a
/// progress bar and a focus-scale animation (matches Card.kt's spring).
class ContinueWatchingPoster extends StatefulWidget {
  final PlexServer server;
  final PlexOnDeckItem item;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final FocusNode? focusNode;
  final bool autofocus;
  final int staggerDelayMs;

  const ContinueWatchingPoster({
    super.key,
    required this.server,
    required this.item,
    required this.onResume,
    required this.onRemove,
    this.focusNode,
    this.autofocus = false,
    this.staggerDelayMs = 0,
  });

  @override
  State<ContinueWatchingPoster> createState() => _ContinueWatchingPosterState();
}

class _ContinueWatchingPosterState extends State<ContinueWatchingPoster> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _confirmingRemove = false;
  late final DpadLongPressDetector _longPress = DpadLongPressDetector(onLongPress: _openConfirm);

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'continue-watching-poster');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    _longPress.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    if (_focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCardVisible(context);
      });
    }
  }

  void _openConfirm() => setState(() => _confirmingRemove = true);

  void _closeConfirm() {
    setState(() => _confirmingRemove = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      handleDpadSelect(event, longPress: _longPress, onClick: widget.onResume);

  @override
  Widget build(BuildContext context) {
    final progress = progressFraction(widget.item);

    return BackHandler(
      enabled: _confirmingRemove,
      onBack: _closeConfirm,
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedScale(
                scale: _focused ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: CustomPaint(
                  // A crisp width-pt stroke, matching every other card's
                  // border via GradientBorderPainter — the previous
                  // Container(border + gradient-fill + padding) combo drew
                  // both a border stroke AND a solid-filled padded band,
                  // reading visibly thicker than the rest of the app's cards.
                  foregroundPainter: _focused
                      ? GradientBorderPainter(shape: _continueWatchingShape, gradient: AppFocusTreatment.focusedGradient, width: AppShape.borderWidth)
                      : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Focus(
                      focusNode: _focusNode,
                      autofocus: widget.autofocus,
                      onKeyEvent: _handleKeyEvent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _focusNode.requestFocus();
                          if (!_confirmingRemove) widget.onResume();
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Artwork(imageUrl: PlexImageUrl.of(widget.server, widget.item.thumb), staggerDelayMs: widget.staggerDelayMs),
                            if (_focused && !_confirmingRemove)
                              Positioned(
                                right: 6,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.scrim.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                                  child: AppText(formatTimecode(widget.item.viewOffset ?? 0), color: AppColors.white, style: AppTypography.bodySmall),
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 4,
                                color: AppColors.scrim.withValues(alpha: 0.4),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(
                                    height: 4,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [AppColors.accent, AppColors.accentGlow]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_confirmingRemove)
                              RemoveConfirmOverlay(
                                message: 'Remove from Continue Watching?',
                                onConfirm: () {
                                  setState(() => _confirmingRemove = false);
                                  widget.onRemove();
                                },
                                onCancel: _closeConfirm,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppText(continueWatchingLabel(widget.item), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
