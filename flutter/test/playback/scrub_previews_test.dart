import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/playback/scrub_previews.dart';

import '../journeys/harness/fake_plex.dart';

void main() {
  group('BIF', () {
    test('frames by time: the one at or before the position', () {
      final bif = BifPreviews.parse(Uint8List.fromList(FakePlex.bif(60000)))!;
      expect(bif.length, 6);
      expect(bif.frameAt(0)!.atMs, 0);
      expect(bif.frameAt(9999)!.atMs, 0);
      expect(bif.frameAt(10000)!.atMs, 10000);
      expect(bif.frameAt(59000)!.atMs, 50000);
      expect(bif.frameAt(600000)!.atMs, 50000, reason: 'past the end: the last frame');
      expect(bif.frameAt(25000)!.source, isNull);
    });

    test('the same frame is the same image, so it is not decoded again', () {
      final bif = BifPreviews.parse(Uint8List.fromList(FakePlex.bif(60000)))!;
      expect(bif.frameAt(12000)!.image, same(bif.frameAt(19000)!.image));
    });

    test("anything that isn't a BIF is no previews", () {
      expect(BifPreviews.parse(Uint8List(10)), isNull);
      expect(BifPreviews.parse(Uint8List(200)), isNull);
      final truncated = Uint8List.fromList(FakePlex.bif(60000).sublist(0, 70));
      expect(BifPreviews.parse(truncated), isNull);
    });
  });

  group('trickplay', () {
    TrickplayPreviews sheets({int count = 250}) => TrickplayPreviews(
      width: 320,
      height: 180,
      tileWidth: 10,
      tileHeight: 10,
      count: count,
      intervalMs: 10000,
      sheetImage: (n) => NetworkImage('http://den/sheet/$n.jpg'),
    );

    test('a position is a tile: sheet, column and row', () {
      final t = sheets();
      final first = t.frameAt(0)!;
      expect(first.source, const Rect.fromLTWH(0, 0, 320, 180));
      expect((first.image as NetworkImage).url, endsWith('/sheet/0.jpg'));

      final f = t.frameAt(125 * 10000 + 4000)!; // tile 125: sheet 1, tile 25
      expect(f.atMs, 1250000);
      expect((f.image as NetworkImage).url, endsWith('/sheet/1.jpg'));
      expect(f.source, const Rect.fromLTWH(5 * 320, 2 * 180, 320, 180));
    });

    test('past the last tile, the last tile', () {
      expect(sheets().frameAt(99999999)!.atMs, 249 * 10000);
    });

    test('a sheet is one image for all its tiles', () {
      final t = sheets();
      expect(t.frameAt(0)!.image, same(t.frameAt(990000)!.image));
      expect(t.frameAt(0)!.image, isNot(same(t.frameAt(1000000)!.image)));
    });

    test('an empty manifest is no frames', () {
      expect(sheets(count: 0).frameAt(0), isNull);
    });
  });
}
