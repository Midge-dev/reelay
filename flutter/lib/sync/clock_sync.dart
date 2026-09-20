import 'dart:async';

import 'time_utils.dart';

class _Sample {
  final int offsetMs;
  final int rttMs;

  const _Sample(this.offsetMs, this.rttMs);
}

/// NTP-style clock sync: bursts 3 pings 500ms apart on start, then one
/// every 5s; the host echoes its own timestamp in a pong. Offset is
/// estimated as remoteTimestamp - sentAt - rtt/2 (assumes symmetric
/// latency); the lowest-RTT sample of the last 8 wins, not a rolling
/// average. Timing constants copied exactly from ClockSync.kt — any other
/// client (Kotlin or Dart) talking to the same host must agree on these.
class ClockSync {
  static const _windowSize = 8;
  static const _maxAcceptedRttMs = 5000;
  static const _intervalMs = 5000;
  static const _burstSpacingMs = 500;
  static const _burstCount = 3;
  static const _pendingExpiryMs = 10000;

  final void Function(int pingId) sendPing;
  final int Function() _nowMs;

  ClockSync({required this.sendPing, int Function()? nowMsFn}) : _nowMs = nowMsFn ?? nowMs;

  final Map<int, int> _pending = {};
  final List<_Sample> _samples = [];
  Timer? _timer;
  bool _running = false;

  int? get offsetMs => _best()?.offsetMs;
  int? get minRttMs => _best()?.rttMs;

  _Sample? _best() {
    _Sample? best;
    for (final sample in _samples) {
      if (best == null || sample.rttMs < best.rttMs) best = sample;
    }
    return best;
  }

  int hostNowMs() => _nowMs() + (offsetMs ?? 0);

  void start() {
    if (_running) return;
    _running = true;
    _ping();
    _scheduleNext(0);
  }

  void _scheduleNext(int burstsSent) {
    final stillBursting = burstsSent < _burstCount - 1;
    final delayMs = stillBursting ? _burstSpacingMs : _intervalMs;
    _timer = Timer(Duration(milliseconds: delayMs), () {
      _ping();
      _scheduleNext(stillBursting ? burstsSent + 1 : burstsSent);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _pending.clear();
  }

  void _ping() {
    final now = _nowMs();
    _pending.removeWhere((_, sentAt) => now - sentAt > _pendingExpiryMs);
    var pingId = now;
    while (_pending.containsKey(pingId)) {
      pingId++;
    }
    _pending[pingId] = now;
    sendPing(pingId);
  }

  void onPong(int pingId, int remoteTimestampMs) {
    final sentAt = _pending.remove(pingId);
    if (sentAt == null) return;
    final now = _nowMs();
    final rtt = now - sentAt;
    if (rtt < 0 || rtt > _maxAcceptedRttMs) return;
    final offset = remoteTimestampMs - sentAt - (rtt ~/ 2);
    _samples.add(_Sample(offset, rtt));
    if (_samples.length > _windowSize) _samples.removeAt(0);
  }
}
