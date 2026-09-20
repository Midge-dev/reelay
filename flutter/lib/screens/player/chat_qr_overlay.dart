import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../focus/back_handler.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _chatQrDisplayMs = 30000;

/// Ports PlayerScreen.kt's `ChatQrOverlay` — a corner QR code that
/// auto-dismisses itself after 30s or on back.
class ChatQrOverlay extends StatefulWidget {
  final String chatUrl;
  final VoidCallback onDismiss;

  const ChatQrOverlay({super.key, required this.chatUrl, required this.onDismiss});

  @override
  State<ChatQrOverlay> createState() => _ChatQrOverlayState();
}

class _ChatQrOverlayState extends State<ChatQrOverlay> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(const Duration(milliseconds: _chatQrDisplayMs), widget.onDismiss);
  }

  @override
  void didUpdateWidget(covariant ChatQrOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatUrl != widget.chatUrl) {
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(milliseconds: _chatQrDisplayMs), widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: widget.onDismiss,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.scrim.withValues(alpha: 0.9)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const AppText('Join the chat', style: AppTypography.titleMedium, color: AppColors.white),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 120,
                    height: 120,
                    color: AppColors.white,
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(data: widget.chatUrl, backgroundColor: AppColors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
