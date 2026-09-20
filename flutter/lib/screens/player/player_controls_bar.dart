import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../kit/icon.dart';
import '../../kit/icon_button.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../common/time_format.dart';

/// Ports PlayerScreen.kt's `PlayerControlsBar` — the bottom overlay bar:
/// a played/buffered/unplayed progress track (visual only; unlike
/// ExoPlayer's `DefaultTimeBar` this isn't independently D-pad-focusable —
/// seeking happens via the rewind/forward buttons here and, when controls
/// are hidden, the accelerating long-press D-pad shortcut on the screen
/// itself — so no focusable scrub-bar widget was built to duplicate that),
/// the position/duration label, and the button row.
class PlayerControlsBar extends StatelessWidget {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final double bufferedFraction;
  final bool subtitlesAvailable;
  final FocusNode? playPauseFocusNode;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onOpenSubtitles;
  final VoidCallback onOpenBitrate;
  final bool chatAvailable;
  final VoidCallback onOpenChatQr;

  const PlayerControlsBar({
    super.key,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    this.bufferedFraction = 0,
    required this.subtitlesAvailable,
    this.playPauseFocusNode,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
    required this.onOpenSubtitles,
    required this.onOpenBitrate,
    required this.chatAvailable,
    required this.onOpenChatQr,
  });

  @override
  Widget build(BuildContext context) {
    final playedFraction = durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.scrim.withValues(alpha: 0.6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProgressTrack(playedFraction: playedFraction, bufferedFraction: bufferedFraction),
            const SizedBox(height: 12),
            AppText('${formatTimecode(positionMs)} / ${formatTimecode(durationMs)}', color: AppColors.white),
            const SizedBox(height: 12),
            // mainAxisAlignment.center on a mainAxisSize.min Row is a no-op
            // (nothing to center within), and the Column above pins it to
            // the start — Center makes the button group actually center
            // within the bar's full width without affecting the
            // left-aligned/full-width progress track and timecode above it.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(onClick: onRewind, child: const AppIcon(Icons.replay_10, tint: AppColors.white)),
                  const SizedBox(width: 16),
                  AppIconButton(
                    onClick: onPlayPause,
                    focusNode: playPauseFocusNode,
                    child: AppIcon(isPlaying ? Icons.pause : Icons.play_arrow, tint: AppColors.white),
                  ),
                  const SizedBox(width: 16),
                  AppIconButton(onClick: onForward, child: const AppIcon(Icons.forward_10, tint: AppColors.white)),
                  const SizedBox(width: 16),
                  AppIconButton(
                    onClick: onOpenSubtitles,
                    enabled: subtitlesAvailable,
                    child: AppIcon(Icons.closed_caption, tint: AppColors.white.withValues(alpha: subtitlesAvailable ? 1 : 0.5)),
                  ),
                  const SizedBox(width: 16),
                  AppIconButton(onClick: onOpenBitrate, child: const AppIcon(Icons.high_quality, tint: AppColors.white)),
                  const SizedBox(width: 16),
                  AppIconButton(
                    onClick: onOpenChatQr,
                    enabled: chatAvailable,
                    child: AppIcon(Icons.chat_bubble_outline, tint: AppColors.white.withValues(alpha: chatAvailable ? 1 : 0.5)),
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

class _ProgressTrack extends StatelessWidget {
  final double playedFraction;
  final double bufferedFraction;

  const _ProgressTrack({required this.playedFraction, required this.bufferedFraction});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x40FFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: bufferedFraction.clamp(0.0, 1.0),
              child: const ColoredBox(color: Color(0x66FFFFFF)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: playedFraction,
              child: const ColoredBox(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
