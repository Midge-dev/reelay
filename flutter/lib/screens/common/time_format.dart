/// "22 min left" / "1h 12m left" — the remaining-time label used on hero
/// and continue-watching captions. [remainingMs] is expected to already be
/// `duration - viewOffset`, clamped non-negative by the caller.
String formatMinutesLeft(int remainingMs) {
  final totalMinutes = (remainingMs / 60000).round();
  if (totalMinutes < 60) return '$totalMinutes min left';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '${hours}h left' : '${hours}h ${minutes.toString().padLeft(2, '0')}m left';
}

/// Ports ui/common/TimeFormat.kt's `formatTimecode`.
String formatTimecode(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
