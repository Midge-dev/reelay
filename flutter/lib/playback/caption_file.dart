import 'dart:convert';

import 'package:video_player/video_player.dart';

/// A downloaded subtitle file, read into captions the player can draw.
///
/// The bytes are UTF-8 if they decode as UTF-8, else Latin-1 (older SRTs
/// usually are). WebVTT goes to video_player's own reader. SubRip doesn't:
/// that reader gives up silently on quirks real files are full of: a
/// byte-order mark, a doubled blank line (it stops reading there), a `.`
/// before the milliseconds, a missing cue number. One movie's subtitles
/// showed and the next one's didn't.
ClosedCaptionFile captionFileFromBytes(List<int> bytes) {
  var text = _decode(bytes);
  if (text.startsWith('﻿')) text = text.substring(1);
  return text.trimLeft().startsWith('WEBVTT') ? WebVTTCaptionFile(text) : SubRipCaptions(text);
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// A forgiving SubRip reader: a cue is a timing line and the text lines
/// under it, up to a blank line. Cue numbers are optional, and blank lines
/// are ignored wherever they fall.
class SubRipCaptions extends ClosedCaptionFile {
  SubRipCaptions(String text) : captions = _parse(text);

  @override
  final List<Caption> captions;
}

final _timing = RegExp(
  r'(\d+):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?\s*-->\s*(\d+):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?',
);
final _cueNumber = RegExp(r'^\d+$');

List<Caption> _parse(String text) {
  final captions = <Caption>[];
  Duration? start;
  Duration? end;
  final lines = <String>[];

  void finish() {
    final (from, to) = (start, end);
    if (from != null && to != null && to > from) {
      captions.add(Caption(number: captions.length + 1, start: from, end: to, text: lines.join('\n')));
    }
    start = null;
    lines.clear();
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final timing = _timing.firstMatch(line);
    if (timing != null) {
      // No blank line before this cue: the line above was its number.
      if (lines.isNotEmpty && _cueNumber.hasMatch(lines.last)) lines.removeLast();
      finish();
      start = _duration(timing, 1);
      end = _duration(timing, 5);
    } else if (line.isEmpty) {
      finish();
    } else if (start != null) {
      lines.add(line);
    }
  }
  finish();
  return captions;
}

Duration _duration(RegExpMatch m, int first) => Duration(
  hours: int.parse(m[first]!),
  minutes: int.parse(m[first + 1]!),
  seconds: int.parse(m[first + 2]!),
  // ",5" is half a second, not five milliseconds.
  milliseconds: int.parse((m[first + 3] ?? '0').padRight(3, '0')),
);
