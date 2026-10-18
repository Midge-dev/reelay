import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/playback/caption_file.dart';
import 'package:video_player/video_player.dart';

List<Caption> _read(String text) => captionFileFromBytes(utf8.encode(text)).captions;

List<String> _texts(List<Caption> captions) => [for (final c in captions) c.text];

const _clean = '1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nTwo\nlines\n';

void main() {
  test('a clean file', () {
    final captions = _read(_clean);
    expect(_texts(captions), ['Hello', 'Two\nlines']);
    expect(captions.first.start, const Duration(seconds: 1));
    expect(captions.first.end, const Duration(milliseconds: 2500));
  });

  test('a byte-order mark and Windows line endings', () {
    expect(_texts(_read('﻿${_clean.replaceAll('\n', '\r\n')}')), ['Hello', 'Two\nlines']);
  });

  test('doubled blank lines don\'t end the file early', () {
    expect(_texts(_read(_clean.replaceAll('\n\n', '\n\n\n\n'))), ['Hello', 'Two\nlines']);
  });

  test('no blank line between cues, and cues with no number', () {
    const text = '00:00:01,000 --> 00:00:02,000\nOne\n2\n00:00:03,000 --> 00:00:04,000\nTwo\n';
    expect(_texts(_read(text)), ['One', 'Two']);
  });

  test('a dot before the milliseconds, and short milliseconds', () {
    final captions = _read('1\n00:00:01.5 --> 00:00:02.25\nDot\n');
    expect(captions.single.start, const Duration(milliseconds: 1500));
    expect(captions.single.end, const Duration(milliseconds: 2250));
  });

  test('a file that isn\'t UTF-8 is read as Latin-1', () {
    final bytes = latin1.encode('1\n00:00:01,000 --> 00:00:02,000\nCafé, señor\n');
    expect(_texts(captionFileFromBytes(bytes).captions), ['Café, señor']);
  });

  test('a cue that ends before it starts is skipped, the rest still read', () {
    final text = '1\n00:00:05,000 --> 00:00:04,000\nBackwards\n\n$_clean';
    expect(_texts(_read(text)), ['Hello', 'Two\nlines']);
  });

  test('WebVTT still goes to the WebVTT reader', () {
    final file = captionFileFromBytes(utf8.encode('WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nVTT\n'));
    expect(file, isA<WebVTTCaptionFile>());
    expect(_texts(file.captions), ['VTT']);
  });
}
