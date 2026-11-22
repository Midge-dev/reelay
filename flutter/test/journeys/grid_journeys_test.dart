import 'package:flutter_test/flutter_test.dart';

import 'harness/fake_jellyfin.dart';
import 'harness/grids.dart';
import 'harness/journey.dart';

/// Every poster grid, walked with the remote (harness/grids.dart): whole,
/// unclipped focus; Down straight down; the next row peeking while there's
/// more; Up a row at a time; a held Down that keeps up and settles.
///
/// The grids: a library's titles and collections, the Watchlist screen, a
/// collection's page and a person's filmography.
void main() {
  // Enough films for the grids to scroll.
  FakeJellyfin bigLibrary() => FakeJellyfin(extraFilms: 40)..favoriteIds.addAll({for (var i = 1; i <= 40; i++) 'm$i'});

  journey("a library's titles", (j) async {
    await j.openFromRail('Movies');
    await j.wait(const Duration(seconds: 1));
    expect(await j.walkGrid('Movies'), greaterThanOrEqualTo(5), reason: j.why('48 films: several rows'));
  }, server: bigLibrary);

  journey('the Watchlist screen', (j) async {
    await j.openFromRail('Watchlist');
    await j.wait(const Duration(seconds: 1));
    expect(await j.walkGrid('Watchlist'), greaterThanOrEqualTo(5));
  }, server: bigLibrary);

  journey("a library's collections, and a collection's page", (j) async {
    await j.openFromRail('Movies');
    await j.wait(const Duration(seconds: 1));
    await j.up(); // the Titles/Collections switch
    await j.right();
    j.expectFocusOn('Collections');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.down();
    await j.walkGrid('Collections');
    await j.select(); // open the focused collection
    await j.wait(const Duration(seconds: 1));
    await j.walkGrid('a collection');
  });

  journey("a person's filmography", (j) async {
    await j.openFromRail('Movies');
    await j.wait(const Duration(seconds: 1));
    await j.select(); // Arrival
    await j.wait(const Duration(seconds: 1));
    for (var i = 0; i < 6 && !j.screenTexts().contains('Lee Lead'); i++) {
      await j.down();
    }
    for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('Lee Lead') || t == 'L'); i++) {
      await j.right();
    }
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    for (var i = 0; i < 3 && j.focusedGrid == null; i++) {
      await j.down();
    }
    expect(await j.walkGrid('Filmography'), greaterThanOrEqualTo(5), reason: j.why('they are in every film'));
  }, server: bigLibrary);
}
