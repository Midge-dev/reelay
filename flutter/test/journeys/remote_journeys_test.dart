import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../playback/fake_video_player_platform.dart';

import 'harness/fake_jellyfin.dart';
import 'harness/journey.dart';

/// Whole-app journeys with the remote: the real app against a fake
/// Jellyfin server, driven by D-pad, Select and Back. After every press the
/// harness checks that something visible has focus.
///
/// Each group names the docs/focus-navigation-qa-checklist.md item it
/// covers, where there is one.
void main() {
  group('Home', () {
    journey('opening a title from a row and coming Back lands on the same poster', (j) async {
      await j.down(); // the Watchlist row
      j.expectFocusOn('Andor');
      await j.right();
      j.expectFocusOn('Contact');
      await j.select();
      expect(j.shows('Play'), isTrue, reason: j.why('the detail page should be open'));

      await j.back();
      j.expectFocusOn('Contact', because: 'Back returns to where you were');
    });

    journey('Left reaches the rail, and Right comes back to the same poster', (j) async {
      await j.down();
      await j.right(); // Contact
      await j.left(2); // Andor, then the rail
      j.expectFocusOn('Home');
      await j.right();
      j.expectFocusOn('Andor');
    });

    journey('every poster in a row is fully on screen as you move along it (checklist 4, 5)', (j) async {
      await j.down(3); // Recently Finished, Suggestions… whatever the lower rows hold
      for (var i = 0; i < 6; i++) {
        await j.right();
        final rect = j.focusedRect()!;
        final screen = j.tester.view.physicalSize;
        expect(rect.left >= 0 && rect.right <= screen.width && rect.top >= 0 && rect.bottom <= screen.height, isTrue,
            reason: j.why('the focused poster should be fully on screen, is at $rect'));
      }
    });
  });

  group('Libraries', () {
    journey('Movies from the rail: the grid, a film, and Back to the same poster', (j) async {
      await j.left();
      await j.down(3); // Search, Watchlist, Movies
      j.expectFocusOn('Movies');
      await j.select(); // opening a library puts focus on its first title
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn(FakeJellyfin.movieTitles.first);

      await j.right(2);
      await j.down();
      final picked = j.focusedTexts().first;
      await j.select();
      expect(j.shows('Play'), isTrue, reason: j.why('the detail page should be open'));

      await j.back();
      j.expectFocusOn(picked, because: 'Back returns to the poster you opened');
    });

    journey('a show: seasons and episodes, and Back all the way out', (j) async {
      await j.left();
      await j.down(4); // Shows
      j.expectFocusOn('Shows');
      await j.select(); // opening a library puts focus on its first title
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Andor'); // sorted by name
      await j.right();
      j.expectFocusOn('Severance');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('Season 1'), isTrue, reason: j.why('the show page lists its seasons'));
      j.expectFocusOn('Severance 1x2', because: 'a show opens on the next episode to watch');

      // Down through the page reaches the episodes, every move visible.
      for (var i = 0; i < 4; i++) {
        await j.down();
      }
      await j.back();
      j.expectFocusOn('Severance', because: 'Back from the show returns to its poster');
      await j.back();
      j.expectFocusOn('Resume', because: 'Back from a library goes Home');
    });
  });

  group('Removing things (checklist 2, 3)', () {
    journey('removing a watchlist title: confirm, it goes, focus stays in the row', (j) async {
      await j.down();
      j.expectFocusOn('Andor');
      await j.holdSelect();
      expect(j.shows('Remove Andor from your watchlist?'), isTrue, reason: j.why('the confirm should be open'));
      j.expectFocusOn('Remove', because: "the long press's release mustn't confirm it on its own");

      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(j.server.favoriteIds, isNot(contains('s2')), reason: j.why('Andor is off the server watchlist'));
      j.expectFocusOn('Contact', because: 'focus moves to the next title in the row, not to the rail');
    });

    journey('Cancel keeps the title and puts focus back on it', (j) async {
      await j.down();
      await j.holdSelect();
      await j.down(); // Cancel: on a poster-sized card the buttons stack
      j.expectFocusOn('Cancel');
      await j.select();
      expect(j.server.favoriteIds, contains('s2'));
      j.expectFocusOn('Andor');
    });

    journey('Back closes the confirm without removing anything (checklist 1, 8)', (j) async {
      await j.down();
      await j.holdSelect();
      await j.back();
      expect(j.shows('Remove Andor from your watchlist?'), isFalse, reason: j.why('Back closes the confirm'));
      expect(j.server.favoriteIds, contains('s2'));
      j.expectFocusOn('Andor', because: 'closing an overlay returns focus to what opened it, not the rail');
    });
  });

  group('Binging', () {
    String playingNow() => (VideoPlayerPlatform.instance as FakeVideoPlayerPlatform).openedUris.last;

    journey('Next episode plays on through the season and into the next', (j) async {
      await j.openFromRail('Shows');
      await j.right(); // Severance
      await j.select();
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Severance 1x2');
      await j.select(); // the episode's page
      j.expectFocusOn('Play');
      await j.select();
      await j.wait(const Duration(seconds: 2));
      expect(playingNow(), contains('s1-s1-e2'));

      for (final next in ['s1-s1-e3', 's1-s1-e4', 's1-s2-e1']) {
        await j.right(2); // Forward, Next episode
        j.expectFocusOn('Next episode');
        await j.select();
        await j.wait(const Duration(seconds: 2));
        expect(playingNow(), contains(next), reason: j.why('Next episode should be playing $next'));
        expect(j.shows('Next episode'), isTrue, reason: j.why('there is still one after $next'));
      }

      await j.back();
      j.expectFocusOn('Play', because: 'Back from the player returns to the page it was started from');
    });

    journey('no Next episode on the last one', (j) async {
      await j.openFromRail('Shows');
      await j.select(); // Andor: one season of three
      await j.wait(const Duration(seconds: 1));
      await j.down(2); // to its last episode
      await j.select();
      await j.select(); // Play
      await j.wait(const Duration(seconds: 2));
      expect(playingNow(), contains('s2-s1-e3'), reason: j.why('should be playing Andor 1x3, the last episode'));
      expect(j.shows('Next episode'), isFalse, reason: j.why('nothing comes after the last episode'));
    });
  });

  group('Panels (checklist 1, 8)', () {
    journey('Back closes the Watch Together panel, back to the page you were on', (j) async {
      await j.openFromRail('Watch Together');
      expect(j.shows('No rooms are live'), isTrue, reason: j.why('the rooms panel should be open'));
      await j.back();
      expect(j.shows('No rooms are live'), isFalse, reason: j.why('Back closes it'));
      // Deliberate (AppNavigationDrawer._closeRooms): the panel hands focus
      // to the page, not back to the rail item that opened it.
      j.expectFocusOn('Resume');
    });
  });

  group('Errors', () {
    journey(
      "Back always leaves an error screen — a watchlist title that isn't on any server",
      (j) async {
        await j.down();
        await j.right(); // Contact, which no server here can find
        await j.select();
        expect(j.shows("isn't on any of your servers"), isTrue, reason: j.why('the error should show'));
        j.expectFocusOn('Go back', because: 'an error always gives the remote a way out');

        await j.back();
        expect(j.shows("isn't on any of your servers"), isFalse, reason: j.why('Back should leave the error screen'));
        j.expectFocusOn('Contact');
      },
      server: () => FakeJellyfin(unfindable: {'m3'}),
    );

    journey(
      "the error's Go back returns to where you were",
      (j) async {
        await j.down();
        await j.right(); // Contact
        await j.select();
        await j.select(); // Go back
        expect(j.shows("isn't on any of your servers"), isFalse, reason: j.why('Go back should leave the error screen'));
        j.expectFocusOn('Contact');
      },
      server: () => FakeJellyfin(unfindable: {'m3'}),
    );
  });
}
