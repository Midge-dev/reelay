import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness/fake_plex.dart';
import 'harness/journey.dart';

/// Opening the app again: Home is there at once, as it was last time,
/// while the servers are asked what's changed — then it updates in place.
void main() {
  journey('a second launch shows the last Home at once, then the fresh one, focus kept', (j) async {
    expect(j.shows('Blade Runner'), isTrue, reason: j.why('Continue Watching on the first launch'));

    // Overnight: Gattaca was started, and the server has become slow to answer.
    j.server.resumeIds.add('m6');
    j.server.latency = const Duration(seconds: 8); // each request; under the client's 15 s timeout
    await j.relaunch(settle: const Duration(seconds: 1));

    expect(j.shows('Blade Runner'), isTrue, reason: j.why("last launch's Home, before the server has answered"));
    expect(j.shows('Gattaca'), isFalse, reason: j.why('the server has not answered yet'));
    expect(j.shows('Looking for your servers'), isFalse, reason: j.why('no connecting screen in front of a saved Home'));

    await j.down(2); // the Watchlist row
    j.expectFocusOn('Andor');
    await j.right();
    j.expectFocusOn('Contact');

    await j.wait(const Duration(seconds: 40)); // the sign-in check, libraries, then the rows
    expect(j.shows('Gattaca'), isTrue, reason: j.why('Home updated from the server'));
    j.expectFocusOn('Contact', because: 'the update keeps focus where you were');
  });

  journey("a saved Home gives way when the server can't be reached", (j) async {
    j.server.answering = false;
    await j.relaunch();
    expect(j.shows('Blade Runner'), isFalse, reason: j.why("the server didn't answer: its titles can't be played"));
    expect(j.shows('Try again now'), isTrue, reason: j.why('the no-servers screen, as without a saved Home'));
  });

  journey('the saved Home keeps no server tokens in plain settings', (j) async {
    final saved = await SharedPreferencesAsync().getAll();
    final text = saved.values.join('\n');
    expect(text, contains('Blade Runner'), reason: 'Home was saved');
    expect(text, isNot(contains('jf-token')), reason: 'tokens belong in the secure store');
  });

  journey('on Plex too, with the server\'s own token kept secure', (j) async {
    expect(j.savedTokens['home:p1'], contains(FakePlex.serverToken), reason: "the Attic server's token, not the account's");
    final saved = (await SharedPreferencesAsync().getAll()).values.join('\n');
    expect(saved, isNot(contains(FakePlex.serverToken)));
    expect(saved, isNot(contains(FakePlex.accountToken)));

    j.plex.latency = const Duration(seconds: 3);
    await j.relaunch(settle: const Duration(seconds: 1));
    expect(j.shows('Severance'), isTrue, reason: j.why("last launch's Continue Watching, before Attic answers"));
    expect(j.shows('Looking for your servers'), isFalse, reason: j.why('no connecting screen in front of a saved Home'));

    await j.wait(const Duration(seconds: 40));
    expect(j.shows('Severance'), isTrue, reason: j.why('still Home once Attic has answered'));
  }, plex: FakePlex.new, jellyfin: false);

  group('posters', () {
    List<String> imageRequests(Journey j, String marker) => [
      for (final r in j.network.requests)
        if (r.uri.path.contains(marker)) '${r.uri.path}?${r.uri.query}',
    ];

    journey('a second launch takes Home\'s posters from the disk, not the server', (j) async {
      final first = imageRequests(j, '/Images/');
      expect(first, isNotEmpty, reason: j.why('the first launch fetched posters'));

      j.network.requests.clear();
      await j.relaunch();
      final again = imageRequests(j, '/Images/');
      expect(again.where(first.contains), isEmpty, reason: j.why('every poster seen last time came off the disk: $again'));
    });

    journey('on Plex, saved posters carry no token', (j) async {
      final first = imageRequests(j, '/photo/:/transcode');
      expect(first, isNotEmpty, reason: j.why('the first launch fetched posters'));
      expect(j.savedArtworkKeys, isNotEmpty);
      expect(j.savedArtworkKeys.join(' '), isNot(contains(FakePlex.serverToken)));

      j.network.requests.clear();
      await j.relaunch();
      expect(imageRequests(j, '/photo/:/transcode').where(first.contains), isEmpty, reason: j.why('posters came off the disk'));
    }, plex: FakePlex.new, jellyfin: false);
  });
}
