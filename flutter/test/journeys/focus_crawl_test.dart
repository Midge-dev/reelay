import 'package:flutter_test/flutter_test.dart';

import 'harness/journey.dart';

/// The focus crawler: on each screen, a few hundred seeded-random D-pad
/// presses. After every one something visible must have focus (not off
/// screen, not inside something faded out); at the end, nowhere it went may
/// be a dead end that no direction leaves. Each screen runs on the Shield's
/// 960×540 canvas at 100%, 130% (the default) and 150% UI size — a layout
/// that overflows fails the test on its own.
void main() {
  final screens = <String, Future<void> Function(Journey j)>{
    'Home': (j) async {},
    'Search': (j) => j.openFromRail('Search'),
    'Watchlist': (j) => j.openFromRail('Watchlist'),
    'Movies': (j) => j.openFromRail('Movies'),
    'Shows': (j) => j.openFromRail('Shows'),
    'Watch Together': (j) => j.openFromRail('Watch Together'),
    'Settings': (j) => j.openFromRail('Settings'),
    'a film': (j) async {
      await j.openFromRail('Movies');
      await j.select();
      await j.wait(const Duration(seconds: 1));
    },
    'a show': (j) async {
      await j.openFromRail('Shows');
      await j.right();
      await j.select();
      await j.wait(const Duration(seconds: 1));
    },
  };

  for (final scale in [1.0, 1.3, 1.5]) {
    group('at ${(scale * 100).round()}% UI size', () {
      for (final MapEntry(key: name, value: goThere) in screens.entries) {
        journey('$name: focus is always visible, and nowhere is a dead end', (j) async {
          await goThere(j);
          for (final seed in [1, 2]) {
            final report = await j.crawl(presses: 120, seed: seed);
            // The rooms panel keeps the arrows inside it and leaves by Back
            // (rooms_panel.dart); with no rooms live it has nothing to move
            // between. Back closing it is its own journey.
            final traps = report.traps.where((t) => !t.contains('No rooms are live'));
            expect(traps, isEmpty, reason: j.why('dead ends (no direction moves focus): $traps'));
          }
        }, uiScale: scale);
      }

      journey('the player on an episode (Next episode in the row): focus stays visible', (j) async {
        await j.openFromRail('Shows');
        await j.right(); // Severance
        await j.select();
        await j.wait(const Duration(seconds: 1));
        await j.select(); // the show's Play S1 E2
        await j.wait(const Duration(seconds: 2));
        expect(j.shows('Next episode'), isTrue, reason: j.why('the episode should have a Next episode button'));
        final report = await j.crawl(presses: 150, pauseEvery: 25);
        expect(report.traps, isEmpty, reason: j.why('dead ends: ${report.traps}'));
      }, uiScale: scale);

      journey('the player: focus stays visible as the controls come and go', (j) async {
        await j.openFromRail('Movies');
        await j.select(); // Arrival
        await j.wait(const Duration(seconds: 1));
        await j.select(); // Play
        await j.wait(const Duration(seconds: 2));
        final report = await j.crawl(presses: 150, pauseEvery: 25);
        expect(report.traps, isEmpty, reason: j.why('dead ends: ${report.traps}'));
      }, uiScale: scale);
    });
  }
}
