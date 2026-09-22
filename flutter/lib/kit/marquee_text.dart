import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/typography.dart';
import 'content_color.dart';

const _startDelay = Duration(milliseconds: 900);
const _endDelay = Duration(milliseconds: 900);
const _pixelsPerSecond = 45.0;

/// A single-line label that scrolls itself horizontally while [active] if
/// (and only if) its text is too wide to fit — revealing the rest of a
/// title a static ellipsis would otherwise cut off, e.g. a poster card's
/// title while its card is focused. Sits still, ellipsized, whenever
/// inactive or already short enough to fit.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color? color;
  final bool active;

  const MarqueeText(this.text, {super.key, this.style = AppTypography.body, this.color, required this.active});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _scrollController = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restart());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active || widget.text != oldWidget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restart());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
    if (widget.active) _scheduleForward();
  }

  void _scheduleForward() {
    _timer = Timer(_startDelay, () async {
      if (!mounted || !_scrollController.hasClients) return;
      final distance = _scrollController.position.maxScrollExtent;
      if (distance <= 0) return;
      await _scrollController.animateTo(
        distance,
        duration: Duration(milliseconds: (distance / _pixelsPerSecond * 1000).round()),
        curve: Curves.linear,
      );
      if (mounted && widget.active) _scheduleBackward();
    });
  }

  void _scheduleBackward() {
    _timer = Timer(_endDelay, () async {
      if (!mounted || !_scrollController.hasClients) return;
      final distance = _scrollController.position.maxScrollExtent;
      await _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: (distance / _pixelsPerSecond * 1000).round()),
        curve: Curves.linear,
      );
      if (mounted && widget.active) _scheduleForward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = widget.style.copyWith(color: widget.color ?? ContentColor.of(context));
    // Inactive: plain ellipsized text (the normal static look — matches
    // every other truncated label in the app) rather than the scrolling
    // viewport, which has nothing to indicate truncation on its own once
    // frozen at rest.
    if (!widget.active) {
      return Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: resolvedStyle);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: resolvedStyle,
      ),
    );
  }
}
