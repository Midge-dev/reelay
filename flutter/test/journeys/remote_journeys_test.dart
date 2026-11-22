import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
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
      await j.down(2); // past More in progress, to the Watchlist row
      j.expectFocusOn('Andor');
      await j.right();
      j.expectFocusOn('Contact');
      await j.select();
      expect(j.shows('Play'), isTrue, reason: j.why('the detail page should be open'));

      await j.back();
      j.expectFocusOn('Contact', because: 'Back returns to where you were');
    });

    journey('Left reaches the rail, and Right comes back to the same poster', (j) async {
      await j.down(2);
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
      j.expectFocusOn('Play S1 E2', because: "a show opens on Play for the next episode to watch");
      final title = j.tester.getRect(find.text('Severance').first);
      expect(title.top >= 0, isTrue, reason: j.why("the show's title is whole on screen, not cut off at the top ($title)"));

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

  group('Collections', () {
    journey("a Jellyfin library's Collections: the server's collections, and opening one shows its films", (j) async {
      await j.openFromRail('Movies');
      await j.wait(const Duration(seconds: 1));
      for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t == 'Titles' || t == 'Collections'); i++) {
        await j.up();
      }
      for (var i = 0; i < 3 && !j.focusedTexts().contains('Collections'); i++) {
        await j.right();
      }
      j.expectFocusOn('Collections', because: "the library's Titles/Collections switch");
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('Sci-fi favourites'), isTrue, reason: j.why('Jellyfin keeps collections in their own view: ${j.screenTexts()}'));
      expect(j.shows('3 titles'), isTrue);
      expect(j.shows('Eighties'), isTrue);

      await j.down(); // into the grid
      for (final step in [j.left, j.right, j.right]) {
        if (j.focusedTexts().contains('Sci-fi favourites')) break;
        await step();
      }
      j.expectFocusOn('Sci-fi favourites');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      for (final film in ['Arrival', 'Ex Machina', 'Interstellar']) {
        expect(j.shows(film), isTrue, reason: j.why('$film is in the collection: ${j.screenTexts()}'));
      }
      expect(j.shows('Contact'), isFalse, reason: j.why('Contact is not'));
    });
  });

  group('Removing things, with Undo (checklist 2, 3; screen 21)', () {
    journey('a hold takes a watchlist title off at once; focus stays in the row; the server hears after Undo runs out', (j) async {
      await j.down(2);
      j.expectFocusOn('Andor');
      await j.holdSelect();
      expect(j.screenTexts(), isNot(contains('Andor')), reason: j.why('Andor is gone at once — no confirm'));
      j.expectFocusOn('Contact', because: 'focus moves to the next title in the row, never to the chip');
      expect(j.shows('Took Andor off the list'), isTrue, reason: j.why('the undo chip shows'));
      expect(j.server.favoriteIds, contains('s2'), reason: j.why('the server hears only once Undo has run out'));

      await j.wait(const Duration(seconds: 9));
      expect(j.server.favoriteIds, isNot(contains('s2')), reason: j.why('Undo ran out: off the server watchlist'));
      expect(j.shows('Took Andor off the list'), isFalse, reason: j.why('the chip expires quietly'));
      j.expectFocusOn('Contact');
    });

    journey('Back while the chip lives puts the title back, and stays on Home', (j) async {
      await j.down(2);
      await j.holdSelect();
      await j.back();
      expect(j.screenTexts(), contains('Andor'), reason: j.why('Back undid it'));
      expect(j.shows('Took Andor off the list'), isFalse);
      expect(j.shows('RESUME'), isTrue, reason: j.why('Back undid, rather than leaving Home'));
      await j.wait(const Duration(seconds: 10));
      expect(j.server.favoriteIds, contains('s2'), reason: j.why('an undone removal never reaches the server'));
    });

    journey('Up reaches the chip; Undo puts the title back and focus with it', (j) async {
      await j.down(2);
      await j.holdSelect();
      for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('Undo')); i++) {
        await j.up();
      }
      j.expectFocusOn('Undo', because: 'Up from the page reaches the chip in its corner');
      await j.select();
      expect(j.screenTexts(), contains('Andor'), reason: j.why('Undo put it back'));
      j.expectFocusOn('Andor', because: 'focus goes back to the row, not off into nothing');
    });

    journey('two removals restate one chip, and Undo takes back the newest', (j) async {
      await j.down(2);
      await j.holdSelect(); // Andor
      await j.holdSelect(); // Contact
      expect(j.shows('Took 2 titles off the list'), isTrue, reason: j.why('one chip, restated: ${j.screenTexts()}'));
      await j.back();
      expect(j.screenTexts(), contains('Contact'), reason: j.why('the newest came back first: ${j.screenTexts()}'));
      expect(j.shows('Took Andor off the list'), isTrue, reason: j.why('the chip restates for the rest'));
    });

    journey("a Next Up episode stays off once Undo runs out — Jellyfin has no hide, so the TV keeps it", (j) async {
      await j.down(); // More in progress: Severance 1x2, Next Up (no position)
      j.expectFocusOn('50 min left');
      await j.holdSelect();
      await j.wait(const Duration(seconds: 9));

      await j.openFromRail('Home'); // Home loads again from the server
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('50 min left'), isFalse, reason: j.why('the server still lists it, but it was taken off: ${j.screenTexts()}'));

      j.server.nextUpEpisode = (1, 3); // you watched on, on another device
      await j.openFromRail('Home');
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('S1 E3 · 50 min left'), isTrue, reason: j.why('a new next episode is a new card'));
    });

    journey('Continue Watching works the same way', (j) async {
      await j.down(); // More in progress: Severance 1x2
      j.expectFocusOn('50 min left');
      await j.holdSelect();
      expect(j.shows('Took Severance off Continue Watching'), isTrue, reason: j.why('the chip names it'));
      expect(j.network.requests.where((r) => r.uri.path.endsWith('/UserData')), isEmpty);
      await j.wait(const Duration(seconds: 9));
      expect(j.network.requests.where((r) => r.uri.path.endsWith('/UserData')), isNotEmpty,
          reason: j.why('Undo ran out: the server is told'));
    });
  });

  group('Binging', () {
    String playingNow() => (VideoPlayerPlatform.instance as FakeVideoPlayerPlatform).openedUris.last;

    journey('Next episode plays on through the season and into the next', (j) async {
      await j.openFromRail('Shows');
      await j.right(); // Severance
      await j.select();
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Play S1 E2');
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
      for (var i = 0; i < 6 && !j.focusedTexts().any((t) => t.contains('Andor 1x3')); i++) {
        await j.down(); // to its last episode
      }
      j.expectFocusOn('Andor 1x3');
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
        await j.down(2);
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
        await j.down(2);
        await j.right(); // Contact
        await j.select();
        await j.select(); // Go back
        expect(j.shows("isn't on any of your servers"), isFalse, reason: j.why('Go back should leave the error screen'));
        j.expectFocusOn('Contact');
      },
      server: () => FakeJellyfin(unfindable: {'m3'}),
    );
  });

  group('Settings', () {
    journey('every category fits on screen, Appearance included', (j) async {
      await j.openFromRail('Settings');
      await j.realTime();
      await j.wait(const Duration(seconds: 1));
      for (final category in ['Playback', 'Subtitles', 'Servers', 'Appearance', 'Display', 'Profiles', 'About']) {
        await j.down();
        j.expectFocusOn(category);
        await j.wait(const Duration(milliseconds: 500));
      }
      // The harness fails the journey on any overflow along the way.
    });

    journey(
      'relay settings: Up and Down reach every relay row, not only Right',
      (j) async {
        await j.openFromRail('Settings');
        await j.realTime();
        await j.wait(const Duration(seconds: 1));
        await j.right(); // into Watch Together, the first category
        for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('Relay server')); i++) {
          await j.down();
        }
        j.expectFocusOn('Relay server');
        await j.select();
        await j.wait(const Duration(seconds: 1));
        j.expectFocusOn('Settings', because: 'the pane opens on its back button');

        double rowOf(String nickname) => j.tester.getRect(find.text(nickname).first).top;
        bool inRow(String nickname, String other) {
          final top = j.focusedRect()!.top;
          return (top - rowOf(nickname)).abs() < (top - rowOf(other)).abs();
        }

        await j.down();
        j.expectFocusOn('Edit', because: "Down from '‹ Settings' lands in the first relay's row");
        expect(inRow('Test relay', 'Cabin Pi'), isTrue, reason: j.why('the first row, not the second'));
        await j.down();
        j.expectFocusOn('Edit', because: 'Down from Edit goes to the Edit below it');
        expect(inRow('Cabin Pi', 'Test relay'), isTrue, reason: j.why("the second relay's row"));
        await j.down();
        j.expectFocusOn('Add a relay');
        await j.up();
        j.expectFocusOn('Make default', because: "Up from Add a relay: the second row, its nearest button");
        await j.up();
        j.expectFocusOn('Edit');
        expect(inRow('Test relay', 'Cabin Pi'), isTrue, reason: j.why('back in the first row'));
        await j.up();
        j.expectFocusOn('Settings');
      },
      relay: true,
      settings: (s) => s.copyWith(relays: [
        ...s.relays,
        const RelayEntry(id: 'r2', nickname: 'Cabin Pi', url: 'ws://cabin.local:8080'),
      ]),
    );
  });
}
