import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/text.dart';
import '../../sync/relay_protocol.dart';
import '../../theme/tokens.dart';

const _messageVisibleMs = 6000;
const _fadeOutMs = 300;
const _maxVisible = 4;

/// Ports ui/common/ChatOverlay.kt — a stack of transient chat bubbles that
/// each fade out on their own timer, newest message pushing the oldest out
/// once [_maxVisible] is exceeded.
class ChatOverlay extends StatefulWidget {
  final Stream<ChatMessage> messages;
  final ChatOverlayCorner corner;

  const ChatOverlay({super.key, required this.messages, this.corner = ChatOverlayCorner.bottomEnd});

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  final _visible = <ChatMessage>[];
  late final StreamSubscription<ChatMessage> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.messages.listen((message) {
      setState(() {
        _visible.add(message);
        if (_visible.length > _maxVisible) _visible.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _expire(ChatMessage message) {
    if (!mounted) return;
    setState(() => _visible.remove(message));
  }

  @override
  Widget build(BuildContext context) {
    final isTop = widget.corner == ChatOverlayCorner.topStart || widget.corner == ChatOverlayCorner.topEnd;
    final isStart = widget.corner == ChatOverlayCorner.topStart || widget.corner == ChatOverlayCorner.bottomStart;
    final ordered = isTop ? _visible.reversed.toList() : _visible;
    final textAlign = isStart ? TextAlign.start : TextAlign.end;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isStart ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        for (final message in ordered) ...[
          _ChatBubble(key: ValueKey(message), message: message, textAlign: textAlign, onExpired: () => _expire(message)),
          if (message != ordered.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final TextAlign textAlign;
  final VoidCallback onExpired;

  const _ChatBubble({super.key, required this.message, required this.textAlign, required this.onExpired});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: _messageVisibleMs), () {
      if (!mounted) return;
      setState(() => _shown = false);
      Future.delayed(const Duration(milliseconds: _fadeOutMs), widget.onExpired);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: _fadeOutMs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppScrims.dialog.withValues(alpha: 0.6)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: AppText(
              '${widget.message.username}: ${widget.message.text}',
              color: AppColors.inkOnArt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: widget.textAlign,
            ),
          ),
        ),
      ),
    );
  }
}
