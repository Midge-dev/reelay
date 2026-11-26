import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/artwork_cache.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('artwork_cache_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List bytes(int n, [int fill = 7]) => Uint8List(n)..fillRange(0, n, fill);

  test('keys drop the Plex token and nothing else', () {
    expect(
      ArtworkCache.keyFor('https://attic:32400/photo/:/transcode?width=320&url=%2Flibrary%2Fmetadata%2F101%2Fthumb%2F17&X-Plex-Token=secret'),
      'https://attic:32400/photo/:/transcode?width=320&url=%2Flibrary%2Fmetadata%2F101%2Fthumb%2F17',
    );
    expect(ArtworkCache.keyFor('http://attic:32400/library/metadata/101/thumb/17?X-Plex-Token=secret'), 'http://attic:32400/library/metadata/101/thumb/17');
    const jellyfin = 'http://den.local:8096/Items/m1/Images/Primary?tag=p-m1&fillWidth=320';
    expect(ArtworkCache.keyFor(jellyfin), jellyfin);
  });

  test('what one launch writes, the next reads back', () async {
    await FileArtworkStore(dir).write('poster-a', bytes(10));
    final later = FileArtworkStore(dir); // a new process: file names must be stable
    expect(await later.read('poster-a'), bytes(10));
    expect(await later.read('poster-b'), isNull);
    expect(dir.listSync().map((f) => f.path).where((p) => p.endsWith('.part')), isEmpty);
  });

  test('past its size, the least recently used go first', () async {
    final store = FileArtworkStore(dir, maxBytes: 3000);
    for (final name in ['old', 'used', 'new']) {
      await store.write(name, bytes(1000));
    }
    final files = {for (final f in dir.listSync().cast<File>()) f.path: f};
    // Make the ages unambiguous: "old" oldest, then "new"; "used" was just read.
    var t = DateTime.now().subtract(const Duration(hours: 3));
    for (final f in files.values) {
      f.setLastModifiedSync(t);
      t = t.add(const Duration(minutes: 1));
    }
    await store.read('used');
    final reread = FileArtworkStore(dir, maxBytes: 3000);
    await reread.write('newest', bytes(1000)); // 4000 bytes now
    // Trims run on start and every 16 MB; start one with the store over.
    final trimmed = FileArtworkStore(dir, maxBytes: 3000);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await trimmed.read('used'), isNotNull, reason: 'just used');
    expect(await trimmed.read('newest'), isNotNull, reason: 'just written');
    final left = dir.listSync().length;
    expect(left, lessThanOrEqualTo(2), reason: 'down to three quarters of 3000 bytes');
  });
}
