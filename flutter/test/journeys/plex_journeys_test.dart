import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../playback/fake_video_player_platform.dart';
import 'harness/fake_plex.dart';
import 'harness/journey.dart';

/// The whole app on a Plex-only profile, against FakePlex: plex.tv (the
/// account, its servers, the Discover watchlist) and one Plex Media Server,
/// "Attic". The same library as the Jellyfin journeys, spoken to the way
/// Plex speaks — so what's checked here is the Plex half of the app:
/// finding the server, reading its hubs, playing and reporting.
void main() {
  group('Plex and Jellyfin together', bothServers);

  void plexJourney(String description, Future<void> Function(Journey j) body, {FakePlex Function()? plex, AppSettings Function(AppSettings)? settings, bool realFonts = false}) =>
      journey(description, body, plex: plex ?? FakePlex.new, jellyfin: false, settings: settings, realFonts: realFonts);

  group('Home', () {
    plexJourney("Home is built from the server's On Deck, hubs and the account's watchlist", (j) async {
      j.expectFocusOn('Resume', because: 'the hero opens on Resume');
      expect(j.shows('Blade Runner'), isTrue, reason: j.why('the hero is the part-watched film: ${j.screenTexts()}'));
      expect(j.shows('1h 07m left'), isTrue, reason: j.why('a third of 100 minutes in'));
      expect(j.shows('Severance'), isTrue, reason: j.why("On Deck's next episode is in Continue Watching"));
      // Poster titles are drawn as bare RichText, which shows() can't see.
      final texts = j.screenTexts();
      expect(texts.contains('Contact') && texts.contains('Andor'), isTrue, reason: j.why('the Discover watchlist, found in the library by guid: ${j.screenTexts()}'));
      expect(j.network.unrouted, isEmpty, reason: j.why('everything the app asked for was served'));
    });

    plexJourney("the rail has the server's Movies and Shows, not its agent-less home videos", (j) async {
      await j.left();
      // The rail names libraries by kind ("Shows"), whatever the server calls them.
      for (final rail in ['Movies', 'Shows']) {
        expect(j.shows(rail), isTrue, reason: j.why('the rail has $rail: ${j.screenTexts()}'));
      }
      expect(j.shows('Home Videos'), isFalse, reason: j.why('an "Other Videos" library has nothing to browse'));
    });
  });

  group('First-run setup', () {
    AppSettings firstRun(AppSettings s) => s.copyWith(setupComplete: false, profiles: const []);

    plexJourney('Plex: the TV shows a code, approving it on plex.tv links the account, and Home has its library', (j) async {
      await j.wait(const Duration(seconds: 1));
      await j.realTime();
      expect(j.shows('STEP 1 OF 4'), isTrue, reason: j.why('a first run opens on setup'));
      j.expectFocusOn('Plex', because: 'Plex starts chosen');
      await j.down();
      j.expectFocusOn('Continue');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      await j.realTime();
      expect(j.shows('STEP 2 OF 4 · PLEX'), isTrue, reason: j.why(j.screenTexts().toString()));
      final code = j.screenTexts().where((t) => t.length == 1).join();
      expect(code, contains(FakePlex.pinCode), reason: j.why("plex.tv's code, to type at plex.tv/link"));
      expect(j.focusOnScreen, isTrue);

      j.plex.linkPin(); // approved on the phone
      for (var i = 0; i < 4 && !j.shows('STEP 3 OF 4'); i++) {
        await j.wait(const Duration(seconds: 3));
        await j.realTime();
      }
      expect(j.shows('STEP 3 OF 4'), isTrue, reason: j.why('the poll saw the approval: ${j.screenTexts()}'));
      for (var i = 0; i < 6 && !j.focusedTexts().contains('Not now'); i++) {
        await j.down();
      }
      j.expectFocusOn('Not now');
      await j.select();
      for (var i = 0; i < 3; i++) {
        await j.realTime();
        await j.wait(const Duration(seconds: 2));
      }
      expect(j.screenTexts(), contains('Blade Runner'), reason: j.why("Home, from Attic: ${j.screenTexts()}"));

      await j.relaunch();
      expect(j.shows('STEP 1 OF 4'), isFalse, reason: j.why('set up once, it stays set up'));
      expect(j.screenTexts(), contains('Blade Runner'), reason: j.why('the token was kept: ${j.screenTexts()}'));
    }, realFonts: true, settings: firstRun);
  });

  group('Finding the server', () {
    plexJourney('the LAN address is used when it answers, though the remote one answers too', (j) async {
      expect(j.plex.lastBaseUrl, FakePlex.lanUrl);
      expect(j.network.requests.where((r) => r.uri.path == '/library/onDeck').single.uri.origin, FakePlex.lanUrl);
    });

    plexJourney('a LAN address a moment slower than the remote one still wins (it gets a 300 ms head start)', (j) async {
      expect(j.network.requests.where((r) => r.uri.path == '/library/onDeck').single.uri.origin, FakePlex.lanUrl,
          reason: j.why('local streams never leave the house'));
    }, plex: () => FakePlex()..lanLatency = const Duration(milliseconds: 150));

    plexJourney('a LAN address far slower than the remote one loses: the start waits no longer than the head start', (j) async {
      expect(j.network.requests.where((r) => r.uri.path == '/library/onDeck').single.uri.origin, FakePlex.remoteUrl);
    }, plex: () => FakePlex()..lanLatency = const Duration(seconds: 2));

    plexJourney('away from home, it reaches the server through its plex.direct address', (j) async {
      expect(j.shows('Blade Runner'), isTrue, reason: j.why('Home loads anyway: ${j.screenTexts()}'));
      expect(j.network.requests.where((r) => r.uri.path == '/library/onDeck').single.uri.origin, FakePlex.remoteUrl);
    }, plex: () => FakePlex(lanReachable: false));

    plexJourney('with only Plex Relay answering, it goes through the relay', (j) async {
      expect(j.shows('Blade Runner'), isTrue, reason: j.why('Home loads anyway: ${j.screenTexts()}'));
      expect(j.network.requests.where((r) => r.uri.path == '/library/onDeck').single.uri.origin, FakePlex.relayUrl);
    }, plex: () => FakePlex(lanReachable: false, remoteReachable: false));

    plexJourney('with nothing answering, the screen says so and has something to press', (j) async {
      expect(j.shows('Blade Runner'), isFalse);
      expect(j.shows('Attic'), isTrue, reason: j.why('the server that did not answer is named: ${j.screenTexts()}'));
      expect(j.focusOnScreen, isTrue, reason: j.why('a way out is focused'));
    }, plex: () => FakePlex(lanReachable: false, remoteReachable: false)..relayReachable = false);

    plexJourney('a sign-in Plex no longer accepts goes back to linking, not to an error', (j) async {
      expect(j.shows('Blade Runner'), isFalse);
      expect(j.shows('plex.tv/link'), isTrue, reason: j.why('linking again is the only way on: ${j.screenTexts()}'));
      expect(j.focusOnScreen, isTrue);
    }, plex: () => FakePlex()..revoked = true);
  });

  group('Playing', () {
    Future<void> resumeBladeRunner(Journey j) async {
      j.expectFocusOn('Resume');
      await j.select();
      await j.wait(const Duration(seconds: 3));
      expect(j.shows('Direct play'), isTrue, reason: j.why('the file direct-plays: ${j.screenTexts()}'));
    }

    plexJourney('Resume direct-plays the file where you left off; the timeline hears, under one session', (j) async {
      await resumeBladeRunner(j);
      final uri = j.video.openedUris.single;
      expect(uri, startsWith('${FakePlex.lanUrl}/library/parts/102/'), reason: j.why('the part itself'));
      expect(uri, contains('X-Plex-Token=${FakePlex.serverToken}'), reason: j.why("the server's token, not the account's"));
      expect(j.video.seeksByPlayer[j.video.latestPlayerId], [FakePlex.filmMs ~/ 3]);

      j.video.setPosition(j.video.latestPlayerId, const Duration(minutes: 50));
      await j.wait(const Duration(seconds: 12));
      expect(j.plex.timelines.map((t) => t.state), contains('playing'), reason: j.why('${j.plex.timelines}'));

      await j.back();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.plex.timelines.last.state, 'stopped', reason: j.why('${j.plex.timelines}'));
      expect(j.plex.timelines.last.timeMs, const Duration(minutes: 50).inMilliseconds);
      expect(j.plex.timelines.map((t) => t.sessionIdentifier).toSet(), hasLength(1),
          reason: j.why('every report names the same session, or PMS shows it wrongly'));
      expect(j.plex.timelines.first.sessionIdentifier, isNotNull);
      j.expectFocusOn('Resume');
      expect(j.shows('50 min left'), isTrue, reason: j.why('the hero shows the new spot: ${j.screenTexts()}'));
    });

    plexJourney('a film played to the end counts as watched and leaves Continue Watching', (j) async {
      await resumeBladeRunner(j);
      final player = j.video.latestPlayerId;
      j.video.setPosition(player, const Duration(minutes: 100));
      j.video.emit(player, VideoEvent(eventType: VideoEventType.completed));
      await j.wait(const Duration(seconds: 2));
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.plex.viewCounts['102'], 1, reason: j.why('PMS counts it watched: ${j.plex.timelines}'));
      expect(j.shows('Direct play'), isFalse, reason: j.why('the player closed'));
      expect(j.shows('1h 07m left'), isFalse, reason: j.why('it has left Continue Watching'));
    });

    plexJourney('a show: its seasons, Play on the On Deck episode, and Skip intro from its markers', (j) async {
      await j.openFromRail('Shows');
      j.expectFocusOn('Andor');
      await j.right();
      j.expectFocusOn('Severance');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('Season 1') && j.shows('Season 2'), isTrue, reason: j.why(j.screenTexts().toString()));
      j.expectFocusOn('Play S1 E2', because: "the show's On Deck episode");
      await j.select();
      await j.wait(const Duration(seconds: 4));
      expect(j.video.openedUris.last, contains('/library/parts/20112/'), reason: j.why('S1 E2 plays'));

      final player = j.video.latestPlayerId;
      j.video.setPosition(player, const Duration(milliseconds: FakePlex.introStartMs + 5000));
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Skip intro', because: "the episode's intro marker is on");
      await j.select();
      expect(j.video.seeksByPlayer[player]!.last, FakePlex.introEndMs);
    });

    plexJourney('a quality cap below the file transcodes: the decision first, then the stream, in one session', (j) async {
      j.expectFocusOn('Resume');
      await j.select();
      await j.wait(const Duration(seconds: 3));
      expect(j.video.openedUris.single, contains('/video/:/transcode/universal/start.m3u8'), reason: j.why('a 2 Mbps cap on an 8 Mbps file'));
      expect(j.video.openedUris.single, contains('maxVideoBitrate=2000'));
      expect(j.plex.transcodes.map((t) => t.split(' ').first).take(1), ['decision'], reason: j.why('${j.plex.transcodes}'));
      final session = j.plex.transcodes.first.split(' ').last;
      expect(j.video.openedUris.single, contains('session=$session'), reason: j.why('the stream is the session the decision approved'));

      await j.back();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.plex.transcodes.last, 'stop $session', reason: j.why('leaving stops the transcode: ${j.plex.transcodes}'));
    }, settings: (s) => s.copyWith(maxVideoBitrateKbps: 2000));

    plexJourney("a transcode Plex refuses, and that then fails to open, says why in Plex's words", (j) async {
      // The decision is advisory: a refused transcode is still tried, and
      // only if the stream then won't open does the error give Plex's reason.
      VideoPlayerPlatform.instance = FakeVideoPlayerPlatform(failInitWhere: (uri) => uri.contains('/transcode/'));
      j.expectFocusOn('Resume');
      await j.select();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();
      expect(j.shows('Transcoder is busy'), isTrue, reason: j.why(j.screenTexts().toString()));
      expect(j.focusOnScreen, isTrue);
    }, plex: () => FakePlex()..transcodeRefusal = 'Transcoder is busy', settings: (s) => s.copyWith(maxVideoBitrateKbps: 2000));
  });

  group('Lists', () {
    plexJourney('a hold takes a title off the watchlist; plex.tv hears once Undo runs out', (j) async {
      await j.down(2);
      j.expectFocusOn('Andor');
      await j.holdSelect();
      expect(j.plex.watchlistGuids, contains('plex://show/s2'), reason: j.why('not yet: Undo is up'));
      await j.wait(const Duration(seconds: 9));
      await j.realTime();
      expect(j.plex.watchlistGuids, isNot(contains('plex://show/s2')), reason: j.why('removed on plex.tv: ${j.network.requests.where((r) => r.uri.host.startsWith('discover'))}'));
    });

    plexJourney('a hold takes a title out of Continue Watching; the server hears once Undo runs out', (j) async {
      await j.down();
      j.expectFocusOn('50 min left', because: 'More in progress: Severance S1 E2, On Deck');
      await j.holdSelect();
      await j.wait(const Duration(seconds: 9));
      await j.realTime();
      expect(j.network.requests.where((r) => r.uri.path == '/actions/removeFromContinueWatching').map((r) => r.uri.queryParameters['ratingKey']), ['2011-2'],
          reason: j.why('PMS is asked to drop it'));
    });

    plexJourney("Search finds the server's titles", (j) async {
      await j.openFromRail('Search');
      await j.wait(const Duration(seconds: 1));
      // Screen 05's keyboard: A–Z in rows of six, focus starting on A.
      j.expectFocusOn('A');
      var (row, col) = (0, 0);
      for (final letter in 'DUN'.split('')) {
        final n = letter.codeUnitAt(0) - 'A'.codeUnitAt(0);
        final (r, c) = (n ~/ 6, n % 6);
        if (r > row) await j.down(r - row);
        if (r < row) await j.up(row - r);
        if (c > col) await j.right(c - col);
        if (c < col) await j.left(col - c);
        (row, col) = (r, c);
        j.expectFocusOn(letter);
        await j.select();
      }
      await j.wait(const Duration(seconds: 2));
      expect(j.shows('Dune'), isTrue, reason: j.why('/hubs/search found it: ${j.screenTexts()}'));
    });
  });
}

/// A profile with both: Plex's Attic and Jellyfin's Den, holding the same
/// films and shows under the same provider ids.
void bothServers() {
  journey('the same titles on Plex and Jellyfin fold: one card, one grid entry, a page with both copies', (j) async {
    final texts = j.screenTexts();
    expect(texts.where((t) => t == 'S1 E2 · 50 min left'), hasLength(1),
        reason: j.why('Severance S1 E2 is On Deck on Attic and Next Up on Den — one card: $texts'));

    await j.openFromRail('Movies');
    expect(j.shows('2 servers'), isTrue, reason: j.why(j.screenTexts().toString()));
    expect(j.shows('8 titles'), isTrue, reason: j.why('eight films, not sixteen'));
    await j.right(); // Blade Runner
    await j.select();
    await j.wait(const Duration(seconds: 2));
    expect(j.shows('2 copies'), isTrue, reason: j.why('the page knows both: ${j.screenTexts()}'));
  }, plex: FakePlex.new);

  // Contact and Andor are on the Plex watchlist and are Jellyfin favorites.
  int count(Journey j, String title) => j.screenTexts().where((t) => t == title).length;

  journey("a title on the Plex watchlist and in Jellyfin's favorites is on the watchlist once", (j) async {
    expect((count(j, 'Contact'), count(j, 'Andor')), (1, 1), reason: j.why("Home's watchlist row: ${j.screenTexts()}"));
    await j.openFromRail('Watchlist');
    expect((count(j, 'Contact'), count(j, 'Andor')), (1, 1), reason: j.why('the Watchlist screen: ${j.screenTexts()}'));
  }, plex: FakePlex.new);

  journey('taking it off takes it off both, so it does not come back from the other list', (j) async {
    await j.down(2);
    j.expectFocusOn('Andor');
    await j.holdSelect();
    await j.wait(const Duration(seconds: 9));
    await j.realTime();
    expect(j.plex.watchlistGuids, isNot(contains('plex://show/s2')), reason: j.why('off the Plex watchlist'));
    expect(j.server.favoriteIds, isNot(contains('s2')), reason: j.why("and out of Jellyfin's favorites"));
    expect(count(j, 'Andor'), 0, reason: j.why('gone from the row: ${j.screenTexts()}'));
  }, plex: FakePlex.new);

  journey("the page's watchlist button takes it off both too", (j) async {
    await j.down(2);
    await j.right();
    j.expectFocusOn('Contact');
    await j.select();
    await j.wait(const Duration(seconds: 1));
    for (var i = 0; i < 4 && !j.shows('Remove from watchlist'); i++) {
      await j.right();
    }
    for (var i = 0; i < 4; i++) {
      try {
        j.expectFocusOn('Remove from watchlist');
        break;
      } on TestFailure {
        await j.right();
      }
    }
    j.expectFocusOn('Remove from watchlist', because: 'the page knows it is on the list');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 1));
    expect(j.plex.watchlistGuids, isNot(contains('plex://movie/m3')), reason: j.why('off the Plex watchlist'));
    expect(j.server.favoriteIds, isNot(contains('m3')), reason: j.why("and out of Jellyfin's favorites"));
  }, plex: FakePlex.new);
}
