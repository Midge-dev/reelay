import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';

import 'harness/journey.dart';

/// First-run setup (screens O1–O5) with the remote, against the fake
/// Jellyfin server: a Jellyfin-only setup typed on the TV, end to end.
/// Plex's sign-in goes through plex.tv, which the fake network doesn't
/// serve. Real fonts: the test font's wide glyphs wrap these pages so much
/// they don't fit the screen, which the app's own type does.
void main() {
  AppSettings firstRun(AppSettings s) => s.copyWith(setupComplete: false, profiles: const []);

  /// Step 1: Jellyfin only (Plex starts chosen), then Continue, then "Type it
  /// on the TV instead" — the typed sign-in, step 2.
  Future<void> toTypedSignIn(Journey j) async {
    await j.wait(const Duration(seconds: 1));
    await j.realTime();
    expect(j.shows('STEP 1 OF 4'), isTrue, reason: j.why('a first run opens on setup'));
    j.expectFocusOn('Plex', because: 'step 1 claims focus on its first choice');
    await j.select(); // Plex off
    await j.right();
    await j.select(); // Jellyfin on
    await j.down();
    j.expectFocusOn('Continue');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.realTime();
    expect(j.shows('STEP 2 OF 4 · JELLYFIN'), isTrue, reason: j.why(j.screenTexts().toString()));
    j.expectFocusOn('Type it on the TV instead', because: 'the phone pairing is up; typing is the focused way out');
    await j.select();
    await j.wait(const Duration(seconds: 1));
  }

  /// The server's address, tested — the keyboard's Done tests it, as
  /// "Test and continue" does, and moves on to the username.
  Future<void> typeAddress(Journey j) async {
    j.expectFocusOn('loft:8096', because: 'the address field, its example showing');
    await j.select();
    await j.type('http://den.local:8096');
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    expect(j.shows('After the address checks out'), isFalse, reason: j.why('Done tested the address: ${j.screenTexts()}'));
  }

  /// Username, then password; Done on each goes on — to the password, then
  /// signing in.
  Future<void> signIn(Journey j, {required String password}) async {
    j.expectFocusOn('Not set', because: 'the address checked out: on to the username');
    final username = j.focusedRect()!;
    await j.select();
    await j.type('sam');
    expect(j.focusedRect()!.top, greaterThan(username.bottom), reason: j.why('Done on the username goes on to the password'));
    j.expectFocusOn('Not set');
    await j.select();
    await j.type(password);
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
  }

  journey('first run, Jellyfin only: typed sign-in, skip Watch Together, and Home has the library', (j) async {
    await toTypedSignIn(j);
    await typeAddress(j);
    await signIn(j, password: 'popcorn');
    expect(j.shows('STEP 3 OF 4'), isTrue, reason: j.why('signed in: on to Watch Together ${j.screenTexts()}'));
    await j.down();
    j.expectFocusOn('Not now');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 3));
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    expect(j.shows('Blade Runner'), isTrue, reason: j.why('Home, from the Jellyfin library: ${j.screenTexts()}'));
    await j.left();
    for (final rail in ['Home', 'Movies', 'Shows']) {
      expect(j.shows(rail), isTrue, reason: j.why('the rail has $rail'));
    }
  }, realFonts: true, settings: firstRun);

  journey('a wrong password says so; a second try signs in', (j) async {
    await toTypedSignIn(j);
    await typeAddress(j);
    await signIn(j, password: 'butter');
    expect(j.shows('The server didn’t accept that username and password.'), isTrue, reason: j.why(j.screenTexts().toString()));
    expect(j.shows('STEP 2 OF 4 · JELLYFIN'), isTrue, reason: j.why('still signing in'));
    expect(j.focusOnScreen, isTrue);

    for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('•')); i++) {
      await j.up(); // back to the password
    }
    await j.select();
    await j.type('popcorn'); // Done signs in
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    expect(j.shows('STEP 3 OF 4'), isTrue, reason: j.why('the second try signed in: ${j.screenTexts()}'));
  }, realFonts: true, settings: firstRun);

  journey('Back walks setup back a step at a time, and never out of the app', (j) async {
    await toTypedSignIn(j);
    await j.back();
    j.expectFocusOn('Type it on the TV instead', because: 'Back from typing returns to the phone pairing');
    await j.back();
    expect(j.shows('STEP 1 OF 4'), isTrue, reason: j.why('Back from step 2 returns to step 1'));
    expect(j.focusOnScreen, isTrue);
    await j.back();
    expect(j.shows('STEP 1 OF 4'), isTrue, reason: j.why('Back on step 1 stays: setup is all there is'));
    expect(j.focusOnScreen, isTrue);
  }, realFonts: true, settings: firstRun);
}
