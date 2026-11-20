/// Where an episode's intro and credits are, as the server knows them: Plex
/// markers (`includeMarkers=1`, found by the server's intro and credits
/// detection), Jellyfin media segments (`/MediaSegments`, from a plugin
/// like Intro Skipper), or, when the server has neither, chapters named
/// like an intro or the credits.
library;

enum SkipKind { intro, credits }

class SkipMarker {
  final SkipKind kind;
  final int startMs;
  final int endMs;

  const SkipMarker(this.kind, this.startMs, this.endMs);

  bool contains(int positionMs) => positionMs >= startMs && positionMs < endMs;

  @override
  bool operator ==(Object other) =>
      other is SkipMarker && other.kind == kind && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(kind, startMs, endMs);

  @override
  String toString() => 'SkipMarker(${kind.name}, $startMs–$endMs)';
}

/// A chapter, as both servers give them: a name and where it starts.
typedef Chapter = ({String? title, int startMs, int? endMs});

// The same chapter names plezy recognises: "Intro", "Introduction",
// "Opening", "OP"/"OP1"; "Credits", "End credits", "Outro", "Closing",
// "Ending", "ED"/"ED2".
final _introName = RegExp(r'(?:^|\b)(?:intro(?:duction)?|opening)(?:\b|$)|^op(?:\s?\d+)?$', caseSensitive: false);
final _creditsName = RegExp(r'(?:^|\b)(?:outro|closing|credits?|ending)(?:\b|$)|^ed(?:\s?\d+)?$', caseSensitive: false);

/// Markers from chapter names. A chapter ends where the next one starts,
/// or at [durationMs] for the last.
List<SkipMarker> markersFromChapters(List<Chapter> chapters, {int? durationMs}) {
  final sorted = [...chapters]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final markers = <SkipMarker>[];
  for (var i = 0; i < sorted.length; i++) {
    final title = sorted[i].title?.trim();
    if (title == null || title.isEmpty) continue;
    // Intro first: "Opening credits" is the intro.
    final kind = _introName.hasMatch(title)
        ? SkipKind.intro
        : _creditsName.hasMatch(title)
        ? SkipKind.credits
        : null;
    if (kind == null) continue;
    final end = sorted[i].endMs ?? (i + 1 < sorted.length ? sorted[i + 1].startMs : durationMs);
    if (end == null || end <= sorted[i].startMs) continue;
    markers.add(SkipMarker(kind, sorted[i].startMs, end));
  }
  return markers;
}

/// The intro [positionMs] is in, if any.
SkipMarker? introAt(List<SkipMarker> markers, int positionMs) {
  for (final m in markers) {
    if (m.kind == SkipKind.intro && m.contains(positionMs)) return m;
  }
  return null;
}

/// Where the end credits start: the last credits marker, if it's in the
/// second half of a [durationMs] runtime — a mislabelled chapter early on
/// mustn't bring Up Next in the middle of an episode.
int? creditsStartMs(List<SkipMarker> markers, int durationMs) {
  int? start;
  for (final m in markers) {
    if (m.kind != SkipKind.credits) continue;
    if (start == null || m.startMs > start) start = m.startMs;
  }
  if (start == null || durationMs <= 0 || start < durationMs / 2) return null;
  return start;
}
