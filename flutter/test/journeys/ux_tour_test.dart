import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness/fake_jellyfin.dart';
import 'harness/journey.dart';

/// A UX tour: the real app, in the app's own type, screenshotted screen by
/// screen on the Shield's 960×540 canvas — for a person (or Claude) to look
/// at, against DESIGN.md. Not a pass/fail test: it runs only when asked.
///
///   UX_TOUR=1 flutter test test/journeys/ux_tour_test.dart
///   UX_TOUR=1 UX_SCALE=1.5 JOURNEY_SHOTS=/tmp/shots flutter test …
///
/// Shots land in build/journey_shots/ (or $JOURNEY_SHOTS), numbered in
/// tour order.
void main() {
  final run = Platform.environment['UX_TOUR'] != null;
  final scale = double.tryParse(Platform.environment['UX_SCALE'] ?? '') ?? 1.3;
  final tag = '${(scale * 100).round()}';
  var n = 0;
  Future<void> shot(Journey j, String name) async {
    n++;
    await j.screenshot('$tag-${n.toString().padLeft(2, '0')}-$name');
  }

  journey('UX tour: browsing', (j) async {
    j.checkFocusAfterEveryPress = false; // a tour, not a test
    await shot(j, 'home');
    await j.down(2);
    await shot(j, 'home-watchlist-row');
    await j.holdSelect();
    await shot(j, 'home-undo-chip');
    await j.back(); // undo
    await j.down(3);
    await shot(j, 'home-lower-rows');

    await j.openFromRail('Search');
    await shot(j, 'search-empty');
    for (var i = 0; i < 3; i++) {
      await j.select();
      await j.right();
    }
    await j.wait(const Duration(seconds: 2));
    await shot(j, 'search-typed');

    await j.openFromRail('Watchlist');
    await shot(j, 'watchlist');

    await j.openFromRail('Movies');
    await shot(j, 'movies-grid');
    await j.up();
    await shot(j, 'movies-filters');
    await j.down();
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'film-page');
    await j.down(2);
    await shot(j, 'film-page-lower');
    await j.down(3);
    await shot(j, 'film-page-bottom');
    await j.back();

    await j.openFromRail('Shows');
    await shot(j, 'shows-grid');
    await j.right();
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'show-page');
    await j.down(2);
    await shot(j, 'show-page-lower');
    await j.up(2);
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'episode-page');
  }, realFonts: true, uiScale: scale, skip: !run);

  journey('UX tour: playing', (j) async {
    j.checkFocusAfterEveryPress = false;
    await j.openFromRail('Shows');
    await j.right();
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select();
    await j.select(); // Play 1x2
    await j.wait(const Duration(seconds: 2));
    await shot(j, 'player-controls');
    await j.wait(const Duration(seconds: 6));
    await shot(j, 'player-clean');
    await j.down();
    await j.right(6); // to the far end of the row: the settings gear
    await shot(j, 'player-controls-right');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'player-menu');
    await j.back();
    await j.wait(const Duration(seconds: 6));
    j.video.setPosition(j.video.latestPlayerId, const Duration(minutes: 99, seconds: 30));
    await j.wait(const Duration(seconds: 2));
    await shot(j, 'player-up-next');
  }, realFonts: true, uiScale: scale, skip: !run);

  journey('UX tour: Watch Together and settings', (j) async {
    j.checkFocusAfterEveryPress = false;
    await j.openFromRail('Movies');
    final riley = j.friend()..host(title: 'Dune', ids: ['imdb://tt00m4'], year: 1995);
    await j.wait(const Duration(seconds: 6));
    await j.realTime();
    await j.left();
    await shot(j, 'rail-new-room-dot');
    riley.leave();
    await j.wait(const Duration(seconds: 6));
    await j.openFromRail('Watch Together');
    await j.realTime();
    await shot(j, 'rooms-panel-empty');
    await j.back();

    await j.openFromRail('Movies');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.right();
    await j.select();
    await j.realTime();
    await shot(j, 'wt-start-dialog');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    j.friend(name: 'Jo').join(j.relay.roomOf('Sam')!.id);
    await j.wait(const Duration(seconds: 4));
    await shot(j, 'lobby-host');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    await shot(j, 'player-in-room');
    await j.wait(const Duration(seconds: 6));
    await shot(j, 'player-in-room-clean');
    await j.back();
    await j.back();
    await j.back();
    await j.wait(const Duration(seconds: 6));
    await j.realTime();
    await shot(j, 'home-room-open');
    await j.down();
    await j.right();
    await j.select();
    await shot(j, 'home-end-confirm');
    await j.back();
    await j.openFromRail('Watch Together');
    await j.realTime();
    await shot(j, 'rooms-panel-mine');
    await j.back();

    await j.openFromRail('Settings');
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'settings');
    for (var i = 0; i < 5; i++) {
      await j.down();
      await shot(j, 'settings-$i');
    }
  }, realFonts: true, uiScale: scale, relay: true, skip: !run);

  journey('UX tour: errors', (j) async {
    j.checkFocusAfterEveryPress = false;
    await j.down(2);
    await j.right(); // Contact: on the watchlist, gone from the server
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await shot(j, 'error-not-on-servers');
  }, realFonts: true, uiScale: scale, skip: !run, server: () => FakeJellyfin(unfindable: {'m3'}));
}
