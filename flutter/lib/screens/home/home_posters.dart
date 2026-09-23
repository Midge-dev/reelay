import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../focus/dpad_long_press.dart';
import '../../kit/scroll_peek.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import '../common/remove_confirm_overlay.dart';
import '../common/time_format.dart';

const _typeEpisode = 'episode';

/// Ports HomeScreen.kt's `recentlyAddedLabel`.
String recentlyAddedLabel(PlexLibraryItem item) {
  final parentTitle = item.parentTitle;
  if (item.type == 'season' && parentTitle != null) return parentTitle;
  return item.title;
}

/// Ports HomeScreen.kt's `continueWatchingLabel`.
String continueWatchingLabel(PlexOnDeckItem item) {
  if (item.type == _typeEpisode &&
      item.grandparentTitle != null &&
      item.parentIndex != null &&
      item.index != null) {
    return '${item.grandparentTitle} · S${item.parentIndex}E${item.index}';
  }
  return item.title;
}

/// The show name for an episode, otherwise the item's own title — the
/// primary line on a hero or "More in progress" card. Nocturne two-line
/// captions split what [continueWatchingLabel] combines into one.
String continueWatchingTitle(PlexOnDeckItem item) {
  if (item.type == _typeEpisode && item.grandparentTitle != null)
    return item.grandparentTitle!;
  return item.title;
}

/// "S3 E1 · 38 min left" — the secondary line under [continueWatchingTitle].
String continueWatchingSubtitle(PlexOnDeckItem item) {
  final parts = <String>[];
  if (item.type == _typeEpisode &&
      item.parentIndex != null &&
      item.index != null) {
    parts.add('S${item.parentIndex} E${item.index}');
  }
  final duration = item.duration;
  if (duration != null && duration > 0) {
    final remaining = duration - (item.viewOffset ?? 0);
    if (remaining > 0) parts.add(formatMinutesLeft(remaining));
  }
  return parts.join(' · ');
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

  const WatchlistPoster({
    super.key,
    required this.server,
    required this.entry,
    required this.onClick,
    required this.onRemove,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<WatchlistPoster> createState() => _WatchlistPosterState();
}

class _WatchlistPosterState extends State<WatchlistPoster> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _confirmingRemove = false;
  late final DpadLongPressDetector _longPress = DpadLongPressDetector(
    onLongPress: _openConfirm,
  );

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      handleDpadSelect(event, longPress: _longPress, onClick: widget.onClick);

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      enabled: _confirmingRemove,
      onBack: _closeConfirm,
      child: SizedBox(
        width: 160.du(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.du(context)),
                child: Container(
                  decoration: BoxDecoration(
                    border: _focused
                        ? Border.all(color: AppColors.accent, width: 2.du(context))
                        : null,
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
                          Artwork(
                            imageUrl: PlexImageUrl.of(
                              widget.server,
                              widget.entry.thumb,
                            ),
                          ),
                          if (_confirmingRemove)
                            RemoveConfirmOverlay(
                              message:
                                  'Remove ${widget.entry.title} from your watchlist?',
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
              padding: EdgeInsets.only(top: 16.du(context)),
              child: AppText(
                widget.entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
  final FoldedWork<PlexOnDeckItem> item;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final FocusNode? focusNode;
  final bool autofocus;

  const ContinueWatchingPoster({
    super.key,
    required this.item,
    required this.onResume,
    required this.onRemove,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<ContinueWatchingPoster> createState() => _ContinueWatchingPosterState();
}

class _ContinueWatchingPosterState extends State<ContinueWatchingPoster> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _confirmingRemove = false;
  late final DpadLongPressDetector _longPress = DpadLongPressDetector(
    onLongPress: _openConfirm,
  );

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode =
        widget.focusNode ?? FocusNode(debugLabel: 'continue-watching-poster');
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) =>
      handleDpadSelect(event, longPress: _longPress, onClick: widget.onResume);

  @override
  Widget build(BuildContext context) {
    final active = widget.item.primary;
    final value = active.value;
    final progress = progressFraction(value);

    final remainingMs = (value.duration ?? 0) - (value.viewOffset ?? 0);

    return BackHandler(
      enabled: _confirmingRemove,
      onBack: _closeConfirm,
      child: SizedBox(
        width: 372.du(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: AnimatedScale(
                scale: _focused ? AppFocusTreatment.focusScale : 1.0,
                duration: AppMotion.focusEnter,
                curve: AppMotion.enter,
                child: Container(
                  // Artwork takes a frame all the way round instead of a
                  // spine on focus — a spine would cover the thumbnail.
                  // DESIGN.md #3.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
                    border: Border.all(
                      color: _focused
                          ? AppFocusTreatment.artFrameColor
                          : AppColors.line,
                      width: (_focused
                              ? AppShape.artFrameWidth
                              : AppShape.borderWidth)
                          .du(context),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.du(context)),
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
                            Artwork(
                              imageUrl: PlexImageUrl.of(
                                active.server,
                                value.thumb,
                              ),
                            ),
                            if (_focused &&
                                !_confirmingRemove &&
                                remainingMs > 0)
                              Positioned(
                                left: 16.du(context),
                                bottom: 16.du(context),
                                child: AppText(
                                  formatMinutesLeft(remainingMs),
                                  color: AppColors.inkOnArt,
                                  style: AppTypography.caption,
                                ),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 4.du(context),
                                color: AppColors.ink.withValues(alpha: 0.22),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: progress,
                                  // Flat fill, not a gradient — DESIGN.md #4/#8.
                                  child: ColoredBox(color: AppColors.accent),
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
              padding: EdgeInsets.only(top: 12.du(context)),
              child: AppText(
                continueWatchingTitle(value),
                style: _focused
                    ? AppTypography.label.copyWith(fontWeight: FontWeight.w500)
                    : AppTypography.label,
                color: _focused ? AppColors.ink : AppColors.ink2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Builder(
              builder: (context) {
                final subtitle = continueWatchingSubtitle(value);
                if (subtitle.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: 3.du(context)),
                  child: AppText(
                    subtitle,
                    style: AppTypography.caption,
                    color: AppColors.ink3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
