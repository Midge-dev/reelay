import 'package:flutter_test/flutter_test.dart';

import 'harness/fake_jellyfin.dart';
import 'harness/journey.dart';

/// Skip intro and credits-timed Up Next, from the server's own markers
/// (FakeJellyfin.segments: Severance has an intro and end credits, Andor
/// has neither).
void main() {
  /// Severance S1 E2, playing, with the controls gone.
  Future<int> playSeverance(Journey j) async {
    await j.openFromRail('Shows');
    await j.right(); // Severance
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select(); // the show's Play S1 E2
    await j.wait(const Duration(seconds: 4)); // the controls hide
    expect(j.video.openedUris.last, contains('s1-s1-e2'));
    return j.video.latestPlayerId;
  }

  Future<void> reach(Journey j, int player, Duration at) async {
    j.video.setPosition(player, at);
    await j.wait(const Duration(seconds: 1));
  }

  const inIntro = Duration(milliseconds: FakeJellyfin.introStartMs + 5000);

  journey('Skip intro comes up in the intro, focused, and one Select skips it', (j) async {
    final player = await playSeverance(j);
    expect(j.shows('Skip intro'), isFalse, reason: j.why('not before the intro'));

    await reach(j, player, inIntro);
    expect(j.shows('Skip intro'), isTrue, reason: j.why('the intro is on: ${j.screenTexts()}'));
    j.expectFocusOn('Skip intro', because: 'with the controls down, one press should skip');

    await j.select();
    expect(j.video.seeksByPlayer[player]!.last, FakeJellyfin.introEndMs, reason: j.why('to the end of the intro'));
    await j.wait(const Duration(seconds: 1));
    expect(j.shows('Skip intro'), isFalse, reason: j.why('skipped, it goes'));
    expect(j.focusOnScreen, isTrue);
  });

  journey('left alone it goes after a few seconds, and comes back with the controls', (j) async {
    final player = await playSeverance(j);
    await reach(j, player, inIntro);
    j.video.setPosition(player, inIntro + const Duration(seconds: 9));
    await j.wait(const Duration(seconds: 9));
    expect(j.shows('Skip intro'), isFalse, reason: j.why("it's had its moment"));

    await j.down(); // the controls come up
    expect(j.shows('Skip intro'), isTrue, reason: j.why('still in the intro, it comes back with the controls'));
    j.expectFocusOn('Pause', because: 'the controls take focus, as always');
    await j.up(); // the progress track
    await j.up();
    j.expectFocusOn('Skip intro', because: 'Up from the progress track reaches it');
    await j.down();
    await j.select(); // Down went back to the track; nothing skipped
    expect(j.video.seeksByPlayer[player] ?? const [], isNot(contains(FakeJellyfin.introEndMs)));
  });

  journey("Back turns it down and stays in the player", (j) async {
    final player = await playSeverance(j);
    await reach(j, player, inIntro);
    j.expectFocusOn('Skip intro');
    await j.back();
    expect(j.shows('Skip intro'), isFalse, reason: j.why('Back dismissed it'));
    expect(j.video.openedUris.last, contains('s1-s1-e2'));
    expect(j.shows('Season 1'), isFalse, reason: j.why('Back took the button away, not the player'));

    await j.down();
    expect(j.shows('Skip intro'), isFalse, reason: j.why('turned down, it stays gone even with the controls'));
  });

  journey('Up Next comes in as the end credits start, not 40 seconds before the end', (j) async {
    final player = await playSeverance(j);
    await reach(j, player, const Duration(milliseconds: FakeJellyfin.creditsStartMs - 10000));
    expect(j.shows('UP NEXT'), isFalse, reason: j.why('not before the credits'));
    await reach(j, player, const Duration(milliseconds: FakeJellyfin.creditsStartMs + 1000));
    expect(j.shows('UP NEXT'), isTrue, reason: j.why('the credits started, four minutes from the end: ${j.screenTexts()}'));
    j.expectFocusOn('Play in', because: 'one press plays the next episode');
  });

  journey("without markers there's no Skip intro, and Up Next waits for the last 40 seconds", (j) async {
    await j.openFromRail('Shows');
    await j.select(); // Andor
    await j.wait(const Duration(seconds: 1));
    await j.select(); // its Play
    await j.wait(const Duration(seconds: 4));
    final player = j.video.latestPlayerId;
    expect(j.video.openedUris.last, contains('s2-s1'));

    await reach(j, player, inIntro);
    expect(j.shows('Skip intro'), isFalse);
    await reach(j, player, const Duration(milliseconds: FakeJellyfin.creditsStartMs + 1000));
    expect(j.shows('UP NEXT'), isFalse, reason: j.why('no credits marker: four minutes out is too early'));
    await reach(j, player, const Duration(minutes: 99, seconds: 30));
    expect(j.shows('UP NEXT'), isTrue);
  });
}
