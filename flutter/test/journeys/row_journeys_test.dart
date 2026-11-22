import 'package:flutter_test/flutter_test.dart';

import 'harness/journey.dart';
import 'harness/rows.dart';

/// Every horizontal row in the app, walked with the remote against
/// DESIGN.md's row rules (see harness/rows.dart): whole and unclipped
/// focus, the 80% stop with the next card peeking, a flush end, one card
/// at a time going back, and a held key that keeps up and then settles.
///
/// The rows: Home's (Continue Watching, Watchlist, Recently Finished,
/// Suggestions, Recently Added), a film's Cast & crew and More like this,
/// Search's results, and a library's filter chips.
void main() {
  journey('Home: every row', (j) async {
    await j.down(); // off the hero, into the first row
    final walked = await j.walkEveryRow('Home');
    expect(walked.length, greaterThanOrEqualTo(4), reason: j.why('Home has its rows: $walked'));
  });

  journey("a film's page: Cast & crew and More like this", (j) async {
    await j.openFromRail('Movies');
    await j.wait(const Duration(seconds: 1));
    await j.select(); // Arrival
    await j.wait(const Duration(seconds: 1));
    final walked = await j.walkEveryRow('Arrival');
    expect(walked, hasLength(2), reason: j.why('cast and similar titles: $walked'));
  });

  // (A show's page has no horizontal rows; the lobby's seats aren't
  // focusable, so the remote never scrolls them.)

  journey('Search results', (j) async {
    await j.openFromRail('Search');
    // Search starts at two letters: type "ER" on the on-screen keyboard.
    await j.right(4); // E
    await j.select();
    await j.down(2); // Q
    await j.right(); // R
    await j.select();
    await j.wait(const Duration(seconds: 2));
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    expect(j.shows('Interstellar'), isTrue, reason: j.why('"ER" finds films: ${j.screenTexts()}'));
    for (var i = 0; i < 4 && j.focusedRow == null; i++) {
      await j.right(); // off the keyboard's last column, into the results
    }
    final walked = await j.walkEveryRow('Search');
    expect(walked, isNotEmpty, reason: j.why('the results are rows: ${j.screenTexts()}'));
  });

  journey("a library's filter row", (j) async {
    await j.openFromRail('Movies');
    await j.wait(const Duration(seconds: 1));
    await j.up(); // the Titles/Collections switch
    j.expectFocusOn('Titles');
    for (var i = 0; i < 3 && j.focusedRow == null; i++) {
      await j.right(); // along to the filter chips, which scroll
    }
    await j.walkRow('Movies filter row');
  });
}
