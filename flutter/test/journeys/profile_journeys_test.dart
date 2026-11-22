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
