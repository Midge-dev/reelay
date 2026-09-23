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

/// "1h 58m" / "42m" — a title's total runtime, for a detail page's
/// metadata line.
String formatRuntime(int ms) {
  final totalMinutes = ms ~/ 60000;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
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

/// A count as the design writes it: "1,284", not "1284".
String formatCount(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
