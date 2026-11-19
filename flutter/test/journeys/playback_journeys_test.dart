import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'harness/journey.dart';

/// Playing things, start to finish, as the server sees it: where playback
/// starts, what it reports, and what Home and the page show afterwards.
/// (Streams, subtitles and transcodes are in
/// test/screens/player/player_playback_test.dart.)
void main() {
  /// Home's hero (Blade Runner, a third in) → its page → Resume.
  Future<void> resumeBladeRunner(Journey j) async {
    j.expectFocusOn('Resume');
    await j.select(); // the hero opens the film's page
    await j.wait(const Duration(seconds: 1));
    j.expectFocusOn('Resume', because: "the page's own Resume is ready to press");
    await j.select();
    await j.wait(const Duration(seconds: 3));
  }

  journey('Resume starts where you left off, and Back saves the new spot', (j) async {
    await resumeBladeRunner(j);
    expect(j.video.openedUris.single, contains('/Videos/m2/'));
    expect(j.video.seeksByPlayer[j.video.latestPlayerId], [const Duration(minutes: 33, seconds: 20).inMilliseconds],
        reason: j.why('Blade Runner was a third of the way in (33:20 of 100 minutes)'));
    await j.wait(const Duration(seconds: 2));
    expect(j.server.playbackReports.map((r) => r.kind).firstOrNull, 'start', reason: j.why('playback reports its start: ${j.server.playbackReports}'));

    j.video.setPosition(j.video.latestPlayerId, const Duration(minutes: 50));
    await j.wait(const Duration(seconds: 12)); // a progress report or two
    expect(j.server.playbackReports.map((r) => r.kind), contains('progress'));

    await j.back();
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    expect(j.server.playbackReports.last.kind, 'stopped');
    expect(j.server.playbackReports.last.positionMs, const Duration(minutes: 50).inMilliseconds);
    j.expectFocusOn('Resume', because: 'Back returns to the page, on the button you pressed');
    expect(j.shows('50 min left'), isTrue, reason: j.why('the page shows the new spot: ${j.screenTexts()}'));
  });

  journey('a film played to the end closes the player and counts as watched', (j) async {
    await resumeBladeRunner(j);
    final player = j.video.latestPlayerId;
    j.video.setPosition(player, const Duration(minutes: 100));
    j.video.emit(player, VideoEvent(eventType: VideoEventType.completed));
    await j.wait(const Duration(seconds: 2));
    await j.realTime();
    await j.wait(const Duration(seconds: 2));

    expect(j.server.playbackReports.last.kind, 'stopped', reason: j.why('the end is reported'));
    expect(j.server.playedIds, contains('m2'), reason: j.why('the server counts it watched'));
    expect(j.shows('Direct play'), isFalse, reason: j.why('the player should have closed, not sat on the last frame'));
    expect(j.focusOnScreen, isTrue, reason: j.why('focus is back on the page'));
  });

  journey('an episode that ends with Up Next on screen goes straight on to the next', (j) async {
    await j.openFromRail('Shows');
    await j.right(); // Severance
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select(); // 1x2's page
    await j.select(); // Play
    await j.wait(const Duration(seconds: 2));
    expect(j.video.openedUris.last, contains('s1-s1-e2'));

    final player = j.video.latestPlayerId;
    j.video.setPosition(player, const Duration(minutes: 99, seconds: 50));
    await j.wait(const Duration(seconds: 2)); // Up Next appears
    expect(j.shows('UP NEXT'), isTrue, reason: j.why('Up Next shows in the last 40 seconds: ${j.screenTexts()}'));
    j.video.setPosition(player, const Duration(minutes: 100));
    j.video.emit(player, VideoEvent(eventType: VideoEventType.completed));
    await j.wait(const Duration(seconds: 3));
    expect(j.video.openedUris.last, contains('s1-s1-e3'), reason: j.why('the next episode plays without waiting out the countdown'));
  });
}
