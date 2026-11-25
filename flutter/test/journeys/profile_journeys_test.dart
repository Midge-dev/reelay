import 'package:flutter_test/flutter_test.dart';

import 'harness/journey.dart';

/// Profiles with the remote: the add-profile dialog (07b) and the profiles
/// it makes. Real fonts — see setup_journeys_test.dart.
void main() {
  /// Settings → Profiles → Add a profile.
  Future<void> openAddProfile(Journey j) async {
    await j.openFromRail('Settings');
    await j.realTime();
    await j.down(6);
    j.expectFocusOn('Profiles');
    await j.right();
    j.expectFocusOn('Add a profile');
    await j.select();
    await j.wait(const Duration(seconds: 1));
  }

  /// In the open dialog: names the profile Riley and signs it in to the
  /// fake's Jellyfin as riley — typed on the TV (O3b) — then creates it.
  Future<void> addRiley(Journey j) async {
    await j.select();
    await j.type('Riley'); // Done goes on to the Watch Together name
    await j.down(2);
    j.expectFocusOn('Sign in', because: "Jellyfin's Sign in, below Plex's");
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.realTime();
    j.expectFocusOn('Type it on the TV instead');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    await j.select();
    await j.type('http://den.local:8096'); // Done tests the address
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    await j.select();
    await j.type('riley');
    await j.select();
    await j.type('jumanji'); // Done signs in
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
    expect(
      j.shows('Signed in to Den as riley'),
      isTrue,
      reason: j.why('back on the dialog, Jellyfin signed in'),
    );
    await j.down();
    j.expectFocusOn('Create profile');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 2));
  }

  /// The rail's library items, as the rail shows them.
  Future<void> expectRail(
    Journey j, {
    required String profile,
    required bool shows,
  }) async {
    await j.left(2);
    expect(
      j.shows(profile),
      isTrue,
      reason: j.why("$profile's avatar is on the rail"),
    );
    expect(j.shows('Movies'), isTrue, reason: j.why('Movies is on the rail'));
    expect(
      j.shows('Shows'),
      shows,
      reason: j.why(
        "Shows is ${shows ? '' : 'not '}on the rail — $profile's account ${shows ? 'can' : "can't"} reach it",
      ),
    );
  }

  journey(
    'adding a profile signs it in, lists it, and leaves you where you were',
    (j) async {
      await openAddProfile(j);
      await addRiley(j);
      expect(
        j.shows("Who's joining this device?"),
        isFalse,
        reason: j.why('the dialog closed'),
      );
      j.expectFocusOn(
        'Add a profile',
        because: 'closing the dialog gives focus back to what opened it',
      );
      expect(
        j.shows('Riley'),
        isTrue,
        reason: j.why('Riley is listed under Profiles'),
      );
      await expectRail(j, profile: 'Sam', shows: true);
    },
    realFonts: true,
  );

  journey('one profile never sees the picker', (j) async {
    await j.relaunch();
    expect(
      j.shows("Who's watching?"),
      isFalse,
      reason: j.why('a one-person household opens straight on Home'),
    );
    await expectRail(j, profile: 'Sam', shows: true);
  }, realFonts: true);

  journey(
    "with two profiles the app opens on Who's watching?, and each opens its own hub",
    (j) async {
      await openAddProfile(j);
      await addRiley(j);
      await j.relaunch();
      expect(
        j.shows("Who's watching?"),
        isTrue,
        reason: j.why('a second profile brings the picker'),
      );
      expect(
        j.shows('Movies'),
        isFalse,
        reason: j.why('the picker is nothing but the choice — no rail'),
      );
      j.expectFocusOn(
        'Sam',
        because:
            'the picker opens on its first profile, named for a screen reader',
      );
      await j.right();
      j.expectFocusOn('Riley');
      await j.right();
      j.expectFocusOn(
        'Add a profile',
        because: 'the + circle is named, not blank',
      );
      await j.right();
      j.expectFocusOn('Add a profile', because: 'the row ends there');

      await j.left();
      await j.select(); // Riley
      await j.realTime();
      await j.wait(const Duration(seconds: 5));
      await expectRail(j, profile: 'Riley', shows: false);

      await j.relaunch();
      await j.select(); // Sam
      await j.realTime();
      await j.wait(const Duration(seconds: 5));
      await expectRail(j, profile: 'Sam', shows: true);
    },
    realFonts: true,
  );

  journey(
    "the picker's Add a profile opens the dialog, and Cancel gives focus back",
    (j) async {
      await openAddProfile(j);
      await addRiley(j);
      await j.relaunch();
      await j.right(2);
      j.expectFocusOn('Add a profile');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(
        j.shows("Who's joining this device?"),
        isTrue,
        reason: j.why('the dialog opened over the picker'),
      );
      final name = j.focusedRect()!;
      expect(
        name.width,
        greaterThan(150),
        reason: j.why('focus starts on the Name field ($name)'),
      );
      await j.down(4);
      j.expectFocusOn('Cancel');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(
        j.shows("Who's joining this device?"),
        isFalse,
        reason: j.why('Cancel closed the dialog'),
      );
      j.expectFocusOn(
        'Add a profile',
        because: 'focus goes back to what opened the dialog',
      );
    },
    realFonts: true,
  );

  journey('the add-profile dialog opens whole on screen, focus on a Name field you can see', (j) async {
    await openAddProfile(j);
    final name = j.focusedRect()!;
    expect(name.width, greaterThan(150), reason: j.why('the focused Name field is a whole box, not a caret ($name)'));
    final screen = j.tester.view.physicalSize / j.tester.view.devicePixelRatio;
    for (final button in ['Create profile', 'Cancel']) {
      final rect = j.tester.getRect(find.text(button));
      expect(rect.top >= 0 && rect.bottom <= screen.height, isTrue,
          reason: j.why('"$button" is on screen as the dialog opens ($rect)'));
    }
  }, realFonts: true);
}
