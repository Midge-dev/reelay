import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
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

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppScrims.dialog.withValues(alpha: 0),
            AppScrims.dialog.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24.du(context),
          48.du(context),
          24.du(context),
          16.du(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              focusNode: progressFocusNode,
              onKeyEvent: (node, event) => handleProgressKey(event),
              child: ListenableBuilder(
                listenable: progressFocusNode,
                builder: (context, _) => _ProgressTrack(
                  playedFraction: playedFraction,
                  bufferedFraction: bufferedFraction,
                  focused: progressFocusNode.hasFocus,
                ),
              ),
            ),
            SizedBox(height: 12.du(context)),
            AppText(
              '${formatTimecode(positionMs)} / ${formatTimecode(durationMs)}',
              color: AppColors.inkOnArt,
            ),
            SizedBox(height: 12.du(context)),
            // mainAxisAlignment.center on a mainAxisSize.min Row is a no-op
            // (nothing to center within), and the Column above pins it to
            // the start — Center makes the button group actually center
            // within the bar's full width without affecting the
            // left-aligned/full-width progress track and timecode above it.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  trapped(
                    0,
                    AppIconButton(
                      onClick: onRewind,
                      focusNode: rewindFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.rewind,
                        tint: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    1,
                    AppIconButton(
                      onClick: onPlayPause,
                      focusNode: playPauseFocusNode,
                      child: AppIcon(
                        isPlaying
                            ? PhosphorIconsFill.pause
                            : PhosphorIconsFill.play,
                        tint: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    2,
                    AppIconButton(
                      onClick: onForward,
                      focusNode: forwardFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.fastForward,
                        tint: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    3,
                    AppIconButton(
                      onClick: onCycleSubtitles,
                      enabled: subtitlesAvailable,
                      focusNode: subtitlesFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.closedCaptioning,
                        tint: AppColors.inkOnArt.withValues(
                          alpha: subtitlesAvailable ? 1 : 0.5,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    4,
                    AppIconButton(
                      onClick: onCycleBitrate,
                      focusNode: bitrateFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.monitor,
                        tint: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    5,
                    AppIconButton(
                      onClick: onOpenChatQr,
                      enabled: chatAvailable,
                      focusNode: chatFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.chatCircleText,
                        tint: AppColors.inkOnArt.withValues(
                          alpha: chatAvailable ? 1 : 0.5,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16.du(context)),
                  trapped(
                    6,
                    AppIconButton(
                      onClick: onOpenMenu,
                      focusNode: menuFocusNode,
                      child: AppIcon(
                        PhosphorIconsRegular.gear,
                        tint: AppColors.inkOnArt,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _thumbSize = 14.0;

class _ProgressTrack extends StatelessWidget {
  final double playedFraction;
  final double bufferedFraction;
  final bool focused;

  const _ProgressTrack({
    required this.playedFraction,
    required this.bufferedFraction,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final thumbSize = _thumbSize.du(context);
    return SizedBox(
      height: thumbSize,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final thumbLeft = (trackWidth * playedFraction - thumbSize / 2).clamp(
            0.0,
            trackWidth - thumbSize,
          );
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2.du(context)),
                child: SizedBox(
                  height: 4.du(context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: AppColors.ink.withValues(alpha: 0.22)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: bufferedFraction.clamp(0.0, 1.0),
                        child: ColoredBox(
                          color: AppColors.ink.withValues(alpha: 0.4),
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
              // Reserved and laid out unconditionally so toggling `focused`
              // never changes this row's height/position — only its color
              // changes, avoiding a layout jump on every focus change.
              Positioned(
                left: thumbLeft,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: focused ? AppColors.accent : AppColors.transparent,
                    shape: BoxShape.circle,
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
