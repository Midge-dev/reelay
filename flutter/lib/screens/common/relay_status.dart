import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide ConnectionState;

import '../../kit/button.dart';
import '../../kit/text.dart';
import '../../sync/relay_protocol.dart';
import '../../theme/tokens.dart';

/// Ports ui/common/RelayStatus.kt's `RelayStatus` sealed interface. Only
/// the display widgets (RelayStatusDot/RelayStatusLine) are ported here —
/// `rememberRelayStatus` (driving this off a live RelayClient's
/// ConnectionState, ported below as [RelayStatusTracker]) belongs to the
/// Lobby/Player screens, not Settings, which drives `RelayStatus` itself
/// off a one-shot local timer while testing a newly paired relay.
enum RelayStatus { silent, waking, connectedConfirm, dotOnly, reconnecting, failed }

const _amberGrey = Color(0xFFB89A6A);

const _wakingAtMs = 2000;
const _failedAtMs = 75000;
const _connectedConfirmVisibleMs = 2000;

/// Ports `rememberRelayStatus` — a small stateful derivation of
/// [RelayStatus] from a live [ConnectionState] stream. Compose expresses
/// this as two `LaunchedEffect`s keyed on different inputs, each
/// automatically cancelled and relaunched when its key changes; ported
/// here as one handler per connectionState event that runs the same two
/// pieces of logic in sequence (effect 2's write to `_everConnected`
/// happens first, so effect 1's key naturally sees the up-to-date value —
/// same ordering the two LaunchedEffects settle into in the same
/// recomposition).
class RelayStatusTracker {
  RelayStatusTracker(Stream<ConnectionState> connectionState, {ConnectionState initial = ConnectionState.disconnected})
      : status = ValueNotifier(RelayStatus.silent) {
    _handle(initial);
    _subscription = connectionState.listen(_handle);
  }

  final ValueNotifier<RelayStatus> status;
  late final StreamSubscription<ConnectionState> _subscription;

  bool _everConnected = false;
  bool _lastIsTryingToConnect = false;
  bool _effect1Started = false;
  Timer? _effect1WakingTimer;
  Timer? _effect1FailedTimer;
  Timer? _effect2ResetTimer;

  void _handle(ConnectionState state) {
    // Effect 2: keyed on connectionState itself — always restarts.
    _effect2ResetTimer?.cancel();
    _effect2ResetTimer = null;
    switch (state) {
      case ConnectionState.connected:
        _everConnected = true;
        status.value = RelayStatus.connectedConfirm;
        _effect2ResetTimer = Timer(const Duration(milliseconds: _connectedConfirmVisibleMs), () {
          status.value = RelayStatus.dotOnly;
        });
      case ConnectionState.roomFull:
      case ConnectionState.roomNotFound:
        status.value = RelayStatus.failed;
      default:
        break;
    }

    // Effect 1: keyed on (isTryingToConnect, everConnected) — only
    // restarts when that pair actually changes.
    final isTryingToConnect = state == ConnectionState.connecting || state == ConnectionState.reconnecting;
    if (_effect1Started && isTryingToConnect == _lastIsTryingToConnect) return;
    _effect1Started = true;
    _lastIsTryingToConnect = isTryingToConnect;
    _effect1WakingTimer?.cancel();
    _effect1FailedTimer?.cancel();
    _effect1WakingTimer = null;
    _effect1FailedTimer = null;

    if (!isTryingToConnect) return;
    if (_everConnected) {
      status.value = RelayStatus.reconnecting;
      return;
    }
    status.value = RelayStatus.silent;
    _effect1WakingTimer = Timer(const Duration(milliseconds: _wakingAtMs), () {
      status.value = RelayStatus.waking;
      _effect1FailedTimer = Timer(const Duration(milliseconds: _failedAtMs - _wakingAtMs), () {
        status.value = RelayStatus.failed;
      });
    });
  }

  void dispose() {
    _subscription.cancel();
    _effect1WakingTimer?.cancel();
    _effect1FailedTimer?.cancel();
    _effect2ResetTimer?.cancel();
    status.dispose();
  }
}

class RelayStatusDot extends StatelessWidget {
  final RelayStatus status;

  const RelayStatusDot({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RelayStatus.silent || RelayStatus.failed => AppColors.ink3.withValues(alpha: 0.3),
      RelayStatus.waking => AppColors.accent300,
      RelayStatus.connectedConfirm || RelayStatus.dotOnly => AppColors.accent,
      RelayStatus.reconnecting => _amberGrey,
    };
    return Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }
}

class RelayStatusLine extends StatelessWidget {
  final RelayStatus status;
  final String relayNickname;
  final VoidCallback onRetry;
  final VoidCallback? onHostOnAnother;

  const RelayStatusLine({
    super.key,
    required this.status,
    required this.relayNickname,
    required this.onRetry,
    this.onHostOnAnother,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case RelayStatus.dotOnly:
        return const SizedBox.shrink();
      case RelayStatus.silent:
        return const _IndeterminateSweep();
      case RelayStatus.waking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [_Spinner(), SizedBox(width: 12), AppText('Waking up the relay')],
            ),
            const SizedBox(height: 10),
            const AppText(
              "This can take up to a minute if nobody has used it in a while. Playback works — you'll be synced when it connects.",
              color: AppColors.ink3,
            ),
          ],
        );
      case RelayStatus.connectedConfirm:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 20, height: 20, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accent)),
            const SizedBox(width: 12),
            const AppText('Connected — room is live'),
          ],
        );
      case RelayStatus.reconnecting:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RelayStatusDot(status: RelayStatus.reconnecting),
            const SizedBox(width: 12),
            const AppText('Reconnecting', color: AppColors.ink3),
          ],
        );
      case RelayStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText("Can't reach $relayNickname"),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppOutlinedButton(onClick: onRetry, child: const AppText('Retry')),
                if (onHostOnAnother != null) ...[
                  const SizedBox(width: 16),
                  AppOutlinedButton(onClick: onHostOnAnother!, child: const AppText('Host on another relay')),
                ],
              ],
            ),
          ],
        );
    }
  }
}

class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 900), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(painter: _SpinnerPainter(_controller.value * 360)),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double rotationDegrees;

  _SpinnerPainter(this.rotationDegrees);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = AppColors.accent300.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = AppColors.accent300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    canvas.drawArc(rect, rotationDegrees * math.pi / 180, 90 * math.pi / 180, false, arc);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) => oldDelegate.rotationDegrees != rotationDegrees;
}

class _IndeterminateSweep extends StatefulWidget {
  const _IndeterminateSweep();

  @override
  State<_IndeterminateSweep> createState() => _IndeterminateSweepState();
}

class _IndeterminateSweepState extends State<_IndeterminateSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1400), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 3,
        color: AppColors.surface.withValues(alpha: 0.6),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(painter: _SweepPainter(-0.4 + 1.4 * _controller.value)),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  final double position;

  _SweepPainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final segmentWidth = size.width * 0.38;
    final x = (size.width + segmentWidth) * position - segmentWidth;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [AppColors.accent300.withValues(alpha: 0), AppColors.accent300],
      ).createShader(Rect.fromLTWH(x, 0, segmentWidth, size.height));
    canvas.drawRect(Rect.fromLTWH(x, 0, segmentWidth, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) => oldDelegate.position != position;
}
