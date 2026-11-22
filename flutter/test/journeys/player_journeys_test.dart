import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/journey.dart';

/// The player with the remote: the control row end to end, the scrubber as
/// a real focus target, the controls coming and going, and the menu panel —
/// against screens 13 ("the scrubber is a real focus target … left/right
/// seek … auto-hide after 3s") and 14 ("a right-hand panel … the picture
/// keeps playing").
void main() {
  /// Severance S1 E2 playing, controls up, focus on Play/Pause.
  Future<void> playEpisode(Journey j) async {
    await j.openFromRail('Shows');
    await j.right(); // Severance
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select(); // Play S1 E2
    await j.wait(const Duration(seconds: 1));
    expect(j.videoPlaying, isTrue);
  }

  double focusX(Journey j) => j.focusedRect()!.left;
  Size screen(Journey j) => j.tester.view.physicalSize / j.tester.view.devicePixelRatio;

  /// Presses [move] until focus stops; returns each control's left edge.
  Future<List<double>> walk(Journey j, Future<void> Function() move) async {
    final xs = [focusX(j)];
    for (var i = 0; i < 12; i++) {
      final before = j.focus;
      await move();
      if (j.focus == before) break;
      xs.add(focusX(j));
    }
    return xs;
  }

  journey('the control row: every control in order, and Left/Right stop at its ends', (j) async {
    await playEpisode(j);
    final play = focusX(j);
    final right = await walk(j, j.right);
    final row = [...(await walk(j, j.left)).reversed];
    expect(row, hasLength(7), reason: j.why('rewind, play/pause, forward, next episode, subtitles, quality, menu: $row'));
    for (var i = 1; i < row.length; i++) {
      expect(row[i], greaterThan(row[i - 1]), reason: j.why('the row runs left to right: $row'));
    }
    expect(right.last, row.last, reason: j.why('Right stops at the menu, the row\'s end'));
    expect(row.first, lessThan(play), reason: j.why('Left reaches Rewind, before Play/Pause'));
    expect(j.shows('Play S1 E2'), isFalse, reason: j.why('the ends hold: nothing left the player'));
  });

  journey('the scrubber is a focus target: Up reaches it, Left/Right seek and focus stays, Down comes back', (j) async {
    await playEpisode(j);
    final play = j.focusedRect()!;
    await j.up();
    final scrubber = j.focusedRect()!;
    expect(scrubber.width, greaterThan(screen(j).width / 2), reason: j.why('the scrubber, the long track above the buttons'));
    expect(scrubber.bottom, lessThanOrEqualTo(play.top), reason: j.why('it sits above the row'));

    final seeks = j.video.seeksByPlayer[j.video.latestPlayerId]?.length ?? 0;
    await j.right();
    await j.right();
    expect(j.video.seeksByPlayer[j.video.latestPlayerId]!.length, seeks + 2, reason: j.why('each Right seeks'));
    expect(j.focusedRect(), scrubber, reason: j.why('and focus stays on the scrubber'));
    await j.left();
    expect(j.video.seeksByPlayer[j.video.latestPlayerId]!.length, seeks + 3);

    await j.down();
    expect(j.focusedRect()!.left, play.left, reason: j.why('Down from the scrubber goes to Play/Pause'));
  });

  journey('the controls hide after 3 s; any press brings them back on Play/Pause; hidden, Left/Right seek', (j) async {
    await playEpisode(j);
    final play = j.focusedRect()!;
    await j.wait(const Duration(seconds: 4));
    expect(j.focusedRect()!.width, closeTo(screen(j).width, 1), reason: j.why('hidden: the screen itself holds focus'));

    final seeks = j.video.seeksByPlayer[j.video.latestPlayerId]?.length ?? 0;
    await j.right();
    expect(j.video.seeksByPlayer[j.video.latestPlayerId]!.length, seeks + 1, reason: j.why('hidden, Right seeks at once'));
    expect(j.focusedRect()!.width, closeTo(screen(j).width, 1), reason: j.why('without bringing up the controls'));

    await j.wait(const Duration(seconds: 1));
    await j.down();
    expect(j.focusedRect(), play, reason: j.why('a press brings the controls back, on Play/Pause'));
  });

  journey('the menu (screen 14): a panel on the right, the picture plays on; Back closes just the panel, then leaves', (j) async {
    await playEpisode(j);
    await walk(j, j.right); // to the menu, the row's end
    final menuButton = j.focusedRect()!;
    await j.select();
    await j.wait(const Duration(seconds: 1));
    expect(j.focusedRect()!.left, greaterThan(screen(j).width * 0.6), reason: j.why('focus is in a panel on the right'));
    expect(j.videoPlaying, isTrue, reason: j.why('the picture keeps playing behind the menu'));

    await j.back();
    expect(j.focusedRect(), menuButton, reason: j.why('Back closes the panel, back on the menu button'));
    expect(j.shows('Play S1 E2'), isFalse, reason: j.why('still in the player'));

    await j.back();
    await j.wait(const Duration(seconds: 1));
    j.expectFocusOn('Play S1 E2', because: 'Back from the player returns to the page it was started from');
  });
}
