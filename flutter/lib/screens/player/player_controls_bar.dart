import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../kit/icon.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/time_format.dart';

class _RowButton {
  final FocusNode focusNode;
  final bool enabled;

  const _RowButton(this.focusNode, this.enabled);
}

/// Ports PlayerScreen.kt's `PlayerControlsBar` — the bottom overlay bar: a
/// played/buffered/unplayed progress track, the position/duration label,
/// and the button row.
///
/// The progress track is D-pad-focusable (Up from the button row reaches
/// it, Down returns to play/pause) and Left/Right on it seek — via
/// [onSeekKeyEvent] rather than [onRewind]/[onForward], so a held key
/// accelerates the jump size the same way the hidden-controls D-pad
/// shortcut does (see seekIncrementForHold), instead of repeating the
/// rewind/forward buttons' fixed per-press increment. This deviates from
/// Kotlin's `DefaultTimeBar`, which wasn't independently focusable there
/// either, but was requested directly for this port.
///
/// Every button in the row (and the progress track) gets an explicit
/// edge-trap: directions with nothing to reach are swallowed here, and
/// Left/Right within the
/// button row walk to the next *enabled* neighbor rather than relying on
/// Flutter's default directional-focus policy. That policy has nowhere
/// sane to send focus when it runs off the end of the row or hits a
/// disabled button (e.g. subtitles/chat when unavailable) — it was
/// observed falling back to the screen's own outer Focus node, which shows
/// no focus ring on any button and looks like focus vanished until the
/// controls hide/reshow cycle re-requests it explicitly.
class PlayerControlsBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final double bufferedFraction;
  final bool subtitlesAvailable;
  final String subtitleLabel;
  final String qualityLabel;
  final FocusNode progressFocusNode;
  final FocusNode rewindFocusNode;
  final FocusNode playPauseFocusNode;
  final FocusNode forwardFocusNode;
  final FocusNode subtitlesFocusNode;
  final FocusNode bitrateFocusNode;
  final FocusNode chatFocusNode;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final KeyEventResult Function(KeyEvent event) onSeekKeyEvent;
  final VoidCallback onCycleSubtitles;
  final VoidCallback onCycleBitrate;
  final bool chatAvailable;

  /// A Watch Together session: seeking moves everyone, so it says so.
  final bool inRoom;
  final VoidCallback onOpenChatQr;
  final FocusNode menuFocusNode;
  final VoidCallback onOpenMenu;

  const PlayerControlsBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    this.bufferedFraction = 0,
    required this.subtitlesAvailable,
    required this.subtitleLabel,
    required this.qualityLabel,
    required this.progressFocusNode,
    required this.rewindFocusNode,
    required this.playPauseFocusNode,
    required this.forwardFocusNode,
    required this.subtitlesFocusNode,
    required this.bitrateFocusNode,
    required this.chatFocusNode,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
    required this.onSeekKeyEvent,
    required this.onCycleSubtitles,
    required this.onCycleBitrate,
    required this.chatAvailable,
    this.inRoom = false,
    required this.onOpenChatQr,
    required this.menuFocusNode,
    required this.onOpenMenu,
  });

  @override
  Widget build(BuildContext context) {
    final playedFraction = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    final row = [
      _RowButton(rewindFocusNode, true),
      _RowButton(playPauseFocusNode, true),
      _RowButton(forwardFocusNode, true),
      _RowButton(subtitlesFocusNode, subtitlesAvailable),
      _RowButton(bitrateFocusNode, true),
      _RowButton(chatFocusNode, chatAvailable),
      _RowButton(menuFocusNode, true),
    ];

    KeyEventResult handleRowKey(int index, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        progressFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        for (var i = index + 1; i < row.length; i++) {
          if (row[i].enabled) {
            row[i].focusNode.requestFocus();
            break;
          }
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        for (var i = index - 1; i >= 0; i--) {
          if (row[i].enabled) {
            row[i].focusNode.requestFocus();
            break;
          }
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    KeyEventResult handleProgressKey(KeyEvent event) {
      // A held key repeats as KeyRepeatEvent, not more KeyDownEvents — both
      // must reach onSeekKeyEvent for hold-to-accelerate to work. KeyUpEvent
      // falls through ignored so it bubbles to the screen level, which
      // resets the hold-repeat bookkeeping there.
      if (event is! KeyDownEvent && event is! KeyRepeatEvent)
        return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.arrowDown) {
        playPauseFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        return onSeekKeyEvent(event);
      }
      return KeyEventResult.ignored;
    }

    Widget trapped(int index, Widget child) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) => handleRowKey(index, event),
        child: child,
      );
    }

    final gap = SizedBox(width: 14.du(context));
    return DecoratedBox(
      // Screen 13's bottom scrim: clear at the top, near-solid ground by
      // 78% down, so the controls read over any frame.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.78],
          colors: [
            AppColors.canvas.withValues(alpha: 0),
            AppColors.canvas.withValues(alpha: 0.96),
          ],
        ),
      ),
      child: Padding(
        // The top padding is the room the seek bubble rises into.
        padding: EdgeInsets.fromLTRB(
          64.du(context),
          150.du(context),
          64.du(context),
          56.du(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppText(
                  formatTimecode(positionMs),
                  style: AppTypography.rowLabel.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  color: AppColors.inkOnArt,
                ),
                SizedBox(width: 22.du(context)),
                Expanded(
                  child: Focus(
                    focusNode: progressFocusNode,
                    onKeyEvent: (node, event) => handleProgressKey(event),
                    child: ListenableBuilder(
                      listenable: progressFocusNode,
                      builder: (context, _) => _ProgressTrack(
                        playedFraction: playedFraction,
                        bufferedFraction: bufferedFraction,
                        focused: progressFocusNode.hasFocus,
                        positionLabel: formatTimecode(positionMs),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 22.du(context)),
                AppText(
                  formatTimecode(durationMs),
                  style: AppTypography.rowLabel.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  color: AppColors.ink2,
                ),
              ],
            ),
            SizedBox(height: 26.du(context)),
            Row(
              children: [
                trapped(
                  0,
                  _ControlButton(
                    onClick: onRewind,
                    focusNode: rewindFocusNode,
                    icon: PhosphorIconsRegular.rewind,
                  ),
                ),
                gap,
                trapped(
                  1,
                  _ControlButton(
                    onClick: onPlayPause,
                    focusNode: playPauseFocusNode,
                    icon: isPlaying
                        ? PhosphorIconsFill.pause
                        : PhosphorIconsFill.play,
                  ),
                ),
                gap,
                trapped(
                  2,
                  _ControlButton(
                    onClick: onForward,
                    focusNode: forwardFocusNode,
                    icon: PhosphorIconsRegular.fastForward,
                  ),
                ),
                if (inRoom) ...[
                  SizedBox(width: 24.du(context)),
                  AppText(
                    'Seeking moves the whole room',
                    style: AppTypography.caption,
                    color: AppColors.ink2,
                  ),
                ],
                const Spacer(),
                trapped(
                  3,
                  _ControlButton(
                    onClick: onCycleSubtitles,
                    enabled: subtitlesAvailable,
                    focusNode: subtitlesFocusNode,
                    icon: PhosphorIconsRegular.closedCaptioning,
                    label: subtitleLabel,
                  ),
                ),
                gap,
                trapped(
                  4,
                  _ControlButton(
                    onClick: onCycleBitrate,
                    focusNode: bitrateFocusNode,
                    icon: PhosphorIconsRegular.monitor,
                    label: qualityLabel,
                  ),
                ),
                // Phone chat only exists in a Watch Together session — a
                // permanently disabled button elsewhere is noise.
                if (chatAvailable) ...[
                  gap,
                  trapped(
                    5,
                    _ControlButton(
                      onClick: onOpenChatQr,
                      focusNode: chatFocusNode,
                      icon: PhosphorIconsRegular.chatCircleText,
                    ),
                  ),
                ],
                gap,
                trapped(
                  6,
                  _ControlButton(
                    onClick: onOpenMenu,
                    focusNode: menuFocusNode,
                    icon: PhosphorIconsRegular.gear,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

SurfaceColors get _controlColors => SurfaceColors(
  container: AppColors.canvas.withValues(alpha: 0.72),
  content: AppColors.inkOnArt,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.inkOnArt,
  pressedContainer: AppColors.accent900,
  pressedContent: AppColors.inkOnArt,
);

/// Screen 13's control: a 64 du square for icon-only actions, a pill with
/// the current value beside its icon for the track choices ("English",
/// "20 Mbps"), both on a translucent ground so they read over the picture.
class _ControlButton extends StatelessWidget {
  final VoidCallback onClick;
  final bool enabled;
  final FocusNode focusNode;
  final IconData icon;
  final String? label;

  const _ControlButton({
    required this.onClick,
    this.enabled = true,
    required this.focusNode,
    required this.icon,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final size = 64.du(context);
    final label = this.label;
    return SizedBox(
      height: size,
      width: label == null ? size : null,
      child: FocusableSurface(
        onClick: onClick,
        enabled: enabled,
        focusNode: focusNode,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        colors: _controlColors,
        border: SurfaceBorder(
          idle: SurfaceBorderSide.solid(AppColors.lineStrong),
          focused: SurfaceBorderSide.solid(AppColors.accent),
          noSpine: label == null,
        ),
        child: label == null
            ? AppIcon(icon, size: 26)
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.du(context)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(icon, size: 24),
                    SizedBox(width: AppSpacing.md.du(context)),
                    AppText(label, style: AppTypography.label, color: null),
                  ],
                ),
              ),
      ),
    );
  }
}

const _thumbSize = 12.0;
const _thumbFocusedSize = 20.0;

class _ProgressTrack extends StatelessWidget {
  final double playedFraction;
  final double bufferedFraction;
  final bool focused;
  final String positionLabel;

  const _ProgressTrack({
    required this.playedFraction,
    required this.bufferedFraction,
    this.focused = false,
    required this.positionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final boxHeight = _thumbFocusedSize.du(context);
    final thumbSize = (focused ? _thumbFocusedSize : _thumbSize).du(context);
    final bubbleWidth = 150.du(context);
    return SizedBox(
      height: boxHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final x = trackWidth * playedFraction;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3.du(context)),
                child: SizedBox(
                  height: 6.du(context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: AppColors.inkOnArt.withValues(alpha: 0.22),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: bufferedFraction.clamp(0.0, 1.0),
                        child: ColoredBox(
                          color: AppColors.inkOnArt.withValues(alpha: 0.38),
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: playedFraction,
                        // Flat fill, not a gradient — DESIGN.md #4/#8.
                        child: ColoredBox(color: AppColors.accent),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (x - thumbSize / 2).clamp(0.0, trackWidth - thumbSize),
                top: (boxHeight - thumbSize) / 2,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                    boxShadow: AppElevation.raised,
                  ),
                ),
              ),
              // Focused, the scrubber is a seek target: the time you would
              // land on rides above the thumb.
              if (focused)
                Positioned(
                  left: (x - bubbleWidth / 2).clamp(
                    0.0,
                    trackWidth - bubbleWidth,
                  ),
                  bottom: 34.du(context),
                  width: bubbleWidth,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8.du(context)),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.canvas.withValues(alpha: 0.86),
                      border: Border.all(
                        color: AppColors.lineStrong,
                        width: 1.du(context),
                      ),
                      borderRadius: BorderRadius.circular(
                        AppShape.radiusMd.du(context),
                      ),
                      boxShadow: AppElevation.overlay,
                    ),
                    child: AppText(
                      positionLabel,
                      style: AppTypography.caption,
                      color: AppColors.inkOnArt,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
