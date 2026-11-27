import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/player/scrub_preview.dart';

import 'harness/fake_jellyfin.dart';
import 'harness/fake_plex.dart';
import 'harness/journey.dart';

/// Screen 13: focus the scrubber and a preview frame of where you'd land
/// rides above it, with the time — from Jellyfin's trickplay sheets or
/// Plex's BIF index.
void main() {
  /// Severance S1 E2 playing from the start, focus on the scrubber.
  Future<void> scrubberOnJellyfin(Journey j) async {
    await j.openFromRail('Shows');
    await j.right(); // Severance
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select(); // Play S1 E2
    await j.wait(const Duration(seconds: 2));
    await j.up();
  }

  /// The preview frame on screen, or null.
  ScrubPreviewImage? preview(Journey j) {
    final found = find.byType(ScrubPreviewImage).evaluate();
    return found.isEmpty ? null : found.single.widget as ScrubPreviewImage;
  }

  journey('Jellyfin: the frame above the scrubber is the one where you would land', (j) async {
    await scrubberOnJellyfin(j);
    await j.right(3); // 0:30
    final frame = preview(j)?.frame;
    expect(frame, isNotNull, reason: j.why('a preview frame above the focused scrubber'));
    expect(frame!.atMs, 30000, reason: j.why('the 10 s tile at 0:30'));
    expect(frame.source, isNotNull, reason: 'one tile of a sheet, not the whole sheet');
    expect(frame.source!.left, 3 * 320, reason: 'the fourth tile across');
    expect(j.server.trickplaySheets.first, endsWith('/320/0'), reason: 'the first sheet holds the first 100 tiles');
    expect(j.shows('0:30'), isTrue, reason: j.why('the time rides with it'));

    await j.left();
    expect(preview(j)!.frame!.atMs, 20000, reason: j.why('it follows the scrub back'));
  });

  journey('Jellyfin: no trickplay, just the time', (j) async {
    await scrubberOnJellyfin(j);
    await j.right(3);
    expect(preview(j), isNull, reason: j.why('nothing to show'));
    expect(j.shows('0:30'), isTrue, reason: j.why('the time bubble as before'));
  }, server: () => FakeJellyfin()..trickplay = false);

  journey('Plex: the frame comes from the BIF index', (j) async {
    j.expectFocusOn('Resume');
    await j.select(); // Blade Runner, a third in
    await j.wait(const Duration(seconds: 2)); // under the controls' 3 s auto-hide
    await j.up(); // the scrubber
    await j.right();
    final frame = preview(j)?.frame;
    expect(frame, isNotNull, reason: j.why('a preview frame above the focused scrubber'));
    expect(frame!.atMs, FakePlex.filmMs ~/ 3 + 10000, reason: j.why('the frame 10 s past where it resumed'));
    expect(frame.source, isNull, reason: 'a BIF frame is a whole image');
    expect(j.plex.bifRequests, ['102'], reason: j.why("Blade Runner's part, fetched once"));
  }, plex: FakePlex.new, jellyfin: false);

  journey('the frame is whole on screen at either end of the film', (j) async {
    await scrubberOnJellyfin(j);
    final screen = j.tester.view.physicalSize / j.tester.view.devicePixelRatio;
    Rect previewRect() => j.tester.getRect(find.byType(ScrubPreviewImage));
    await j.right();
    expect(previewRect().left, greaterThanOrEqualTo(0), reason: j.why('near the start'));
    // The fake player's files run 100 minutes.
    j.video.setPosition(j.video.latestPlayerId, const Duration(minutes: 99, seconds: 40));
    await j.right();
    expect(previewRect().right, lessThanOrEqualTo(screen.width), reason: j.why('near the end'));
  });
}
