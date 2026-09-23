/// "22 min left" / "1h 12m left" — the remaining-time label used on hero
/// and continue-watching captions. [remainingMs] is expected to already be
/// `duration - viewOffset`, clamped non-negative by the caller.
String formatMinutesLeft(int remainingMs) {
  final totalMinutes = (remainingMs / 60000).round();
  if (totalMinutes < 60) return '$totalMinutes min left';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0
      ? '${hours}h left'
      : '${hours}h ${minutes.toString().padLeft(2, '0')}m left';
}

/// "1h 58m" / "42m" — a title's total runtime, for a detail page's
/// metadata line.
String formatRuntime(int ms) {
  final totalMinutes = ms ~/ 60000;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

/// "1:11:07", or "46:12" under an hour.
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

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Plex's `originallyAvailableAt` ("2022-12-18") as people write it:
/// "Dec 18, 2022". Anything unparseable is shown as given.
String formatAirDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// "two", "three" — copy spells small counts out ("on three of your
/// servers"); anything past ten stays a numeral.
String countWord(int n) => switch (n) {
  0 => 'no',
  1 => 'one',
  2 => 'two',
  3 => 'three',
  4 => 'four',
  5 => 'five',
  6 => 'six',
  7 => 'seven',
  8 => 'eight',
  9 => 'nine',
  10 => 'ten',
  _ => '$n',
};
