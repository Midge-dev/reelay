import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/player/chat_qr_overlay.dart';

import 'package:reelay/sync/playback_state.dart';

import 'harness/journey.dart';

/// Watch Together, the whole app against an in-process relay
/// (harness/fake_relay.dart) with a friend on another TV — the real relay
/// client, sync logic and presence on a simulated player. The sync rules
/// themselves are tested in test/sync/; these walk the screens around them.
void main() {
  /// From Movies, Arrival's page → Watch Together → Open the room.
  Future<void> hostArrival(Journey j) async {
    await j.openFromRail('Movies');
    await j.select(); // Arrival
    await j.wait(const Duration(seconds: 1));
    await j.right();
    j.expectFocusOn('Watch Together');
    await j.select();
    j.expectFocusOn('Open the room', because: 'the start dialog claims focus');
    expect(j.shows('Start from the beginning'), isFalse,
        reason: j.why('Arrival was never started: no Resume-or-restart choice to make'));
    await j.select();
    await j.realTime(); // the settings store answers on the real clock
    await j.wait(const Duration(seconds: 2));
    expect(j.shows('YOUR ROOM'), isTrue, reason: j.why('the lobby should be open'));
  }

  /// Riley's room, from the rooms panel: Join, and into their lobby.
  Future<void> joinRileysRoom(Journey j) async {
    await j.wait(const Duration(seconds: 20)); // the next directory poll
    await j.realTime();
    await j.openFromRail('Watch Together');
    await j.realTime();
    j.expectFocusOn("Riley's room", because: 'the rooms panel focuses its first room');
    await j.select();
    await j.realTime();
    await j.wait(const Duration(seconds: 3));
    expect(j.shows('RILEY’S ROOM'), isTrue, reason: j.why("Riley's lobby should be open"));
  }

  group('Hosting', () {
    journey('open a room, a friend joins, Start for everyone plays on both TVs', (j) async {
      await hostArrival(j);
      j.expectFocusOn('Start for everyone', because: 'the lobby claims focus on entry');

      final riley = j.friend()..join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      expect(j.shows('Riley'), isTrue, reason: j.why('Riley should be in a seat'));
      expect(j.shows('2 OF 8 SEATS'), isTrue, reason: j.why('two people, and the seat count says so'));

      await j.select(); // Start for everyone
      await j.realTime();
      await j.wait(const Duration(seconds: 3));
      expect(j.video.openedUris.last, contains('/Videos/m1/'), reason: j.why('Arrival should be playing'));
      expect(j.videoPlaying, isTrue, reason: j.why('the host plays'));
      expect(riley.playing, isTrue, reason: j.why('Start for everyone starts Riley too'));
      expect(riley.roomPhase, 'playing');
      await j.wait(const Duration(seconds: 4));
      expect(riley.heard.where((e) => e.kind == 'presence').map((e) => e.username).toSet(), {'Sam'},
          reason: j.why("Riley knows you as your profile's Watch Together name, Sam — never \"You\""));
    }, relay: true);

    journey('pause on the host pauses the friend, and the friend\'s pause pauses the host', (j) async {
      await hostArrival(j);
      final riley = j.friend()..join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await j.select(); // Start for everyone
      await j.realTime();
      await j.wait(const Duration(seconds: 5));

      await j.select(); // with the controls hidden, Select pauses (and shows them)
      await j.wait(const Duration(seconds: 2));
      j.expectFocusOn('Play', because: 'the controls come up on the play/pause button');
      expect(j.videoPlaying, isFalse, reason: j.why('the host paused'));
      expect(riley.playing, isFalse, reason: j.why("the host's pause pauses Riley"));

      await j.select(); // play again
      await j.wait(const Duration(seconds: 3));
      expect(riley.playing, isTrue, reason: j.why("the host's play resumes Riley"));

      riley.pressPause();
      await j.wait(const Duration(seconds: 2));
      expect(j.videoPlaying, isFalse, reason: j.why("Riley's pause pauses the whole room"));
    }, relay: true);

    journey('Back from the player keeps the room open; End on Home ends it for everyone', (j) async {
      await hostArrival(j);
      final riley = j.friend()..join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await j.select(); // Start for everyone
      await j.realTime();
      await j.wait(const Duration(seconds: 3));

      await j.back();
      await j.realTime();
      j.expectFocusOn('Watch Together', because: 'Back returns to the page the room was started from');
      expect(j.relay.rooms, isNotEmpty, reason: j.why("the host's room stays open while they look around"));

      await j.back(); // Movies
      await j.back(); // Home
      await j.wait(const Duration(seconds: 6));
      await j.realTime();
      expect(j.shows('Your room is open'), isTrue, reason: j.why("Home's bar shows the room kept open: \${j.screenTexts()}"));

      await j.down();
      j.expectFocusOn('Go back in', because: "Down from the hero reaches the bar, and its first stop is the safe action, never End");
      await j.down();
      await j.up();
      j.expectFocusOn('Go back in', because: 'Up from the row underneath comes back to the bar, not past it');
      await j.right();
      j.expectFocusOn('End room');
      await j.select();
      await j.screenshot('end-confirm');
      j.expectFocusOn('Keep it open', because: 'ending a room for others is confirmed, and the confirm opens on the safe choice');
      await j.back();
      j.expectFocusOn('End room', because: 'Back keeps the room open and returns to End');
      expect(j.relay.rooms, isNotEmpty);
      await j.select();
      await j.up();
      await j.left();
      j.expectFocusOn('Keep it open', because: 'the arrows stay inside the confirm');
      await j.right();
      j.expectFocusOn('End for everyone');
      await j.select();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.relay.rooms, isEmpty, reason: j.why('the room should be closed on the relay'));
      expect(riley.client.connectionStateValue.name, 'roomClosed', reason: j.why('Riley is told the room ended'));
      expect(j.shows('Your room is open'), isFalse, reason: j.why('the bar no longer shows it'));
    }, relay: true, realFonts: true);
  });

  group('Close the room', () {
    Future<void> toClose(Journey j) async {
      for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('Close the room')); i++) {
        await j.right();
      }
      j.expectFocusOn('Close the room');
    }

    journey('with nobody in it, it closes at once — not kept open', (j) async {
      await hostArrival(j);
      await toClose(j);
      await j.select();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.relay.rooms, isEmpty, reason: j.why('the room should be gone from the relay'));
      j.expectFocusOn('Watch Together', because: "back on the film's page");
    }, relay: true);

    journey('with a friend in it, it asks first; Keep it open, then End for everyone', (j) async {
      await hostArrival(j);
      final riley = j.friend()..join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await toClose(j);
      await j.select();
      j.expectFocusOn('Keep it open', because: 'ending a room for others is confirmed, safe choice first');
      await j.select();
      j.expectFocusOn('Close the room', because: 'Keep it open returns to the button');
      expect(j.relay.rooms, isNotEmpty);

      await j.select();
      await j.right();
      j.expectFocusOn('End for everyone');
      await j.select();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      expect(j.relay.rooms, isEmpty, reason: j.why('ended for everyone'));
      expect(riley.client.connectionStateValue.name, 'roomClosed', reason: j.why('Riley is told'));
    }, relay: true);
  });

  group('The rail says when a room opens', () {
    bool dot(Journey j) => find.byKey(const ValueKey('rail-new-dot')).evaluate().isNotEmpty;

    journey("a friend's room opening while you're in Movies puts a dot on Watch Together; the rooms panel clears it", (j) async {
      await j.openFromRail('Movies');
      expect(dot(j), isFalse);
      j.friend().host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await j.wait(const Duration(seconds: 6)); // the next directory poll
      await j.realTime();
      expect(dot(j), isTrue, reason: j.why('a new room: the rail shows it from any screen'));

      await j.openFromRail('Watch Together');
      await j.realTime();
      await j.back();
      await j.wait(const Duration(seconds: 6));
      expect(dot(j), isFalse, reason: j.why('seen in the rooms panel'));
    }, relay: true);

    journey("Home's bar counts as seeing it", (j) async {
      await j.openFromRail('Movies');
      j.friend().host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await j.wait(const Duration(seconds: 6));
      await j.realTime();
      expect(dot(j), isTrue);
      await j.openFromRail('Home');
      await j.wait(const Duration(seconds: 6));
      await j.realTime();
      expect(dot(j), isFalse, reason: j.why("it's on Home's bar"));
    }, relay: true);

    journey('your own room never gets a dot', (j) async {
      await hostArrival(j);
      await j.back(); // the lobby; the room stays open
      await j.realTime();
      await j.back();
      await j.wait(const Duration(seconds: 6));
      await j.realTime();
      expect(j.relay.rooms, isNotEmpty);
      expect(dot(j), isFalse, reason: j.why('nothing new about your own room'));
    }, relay: true);
  });

  group('Phone chat', () {
    journey('on (the default): the lobby shows its QR, and the player has a chat button', (j) async {
      await hostArrival(j);
      expect(j.shows('Scan to chat'), isTrue, reason: j.why('the QR is in the lobby, no button to find'));
      j.friend().join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await j.select(); // Start for everyone
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      await j.down(); // the controls
      expect(find.bySemanticsLabel('Phone chat'), findsOneWidget, reason: j.why("the player's chat QR button is there"));
    }, relay: true);

    journey("the player's chat button opens the QR; Back closes just the QR, and you stay in the player", (j) async {
      await hostArrival(j);
      j.friend().join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await j.select(); // Start for everyone
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      await j.down(); // the controls
      final chat = j.tester.getRect(find.bySemanticsLabel('Phone chat'));
      for (var i = 0; i < 8 && j.focusedRect() != chat; i++) {
        await j.right();
      }
      expect(j.focusedRect(), chat, reason: j.why('the chat button is on the control row'));
      final qrBefore = find.byType(ChatQrOverlay).evaluate().length;
      await j.select();
      await j.wait(const Duration(milliseconds: 500));
      expect(find.byType(ChatQrOverlay), findsNWidgets(qrBefore + 1), reason: j.why('the QR is up'));

      await j.back();
      expect(find.byType(ChatQrOverlay), findsNWidgets(qrBefore), reason: j.why('Back closed the QR'));
      expect(find.bySemanticsLabel('Phone chat'), findsOneWidget, reason: j.why('and left you in the player'));
    }, relay: true);

    journey('off in Settings: no QR in the lobby, no chat button in the player', (j) async {
      await hostArrival(j);
      expect(j.shows('Scan to chat'), isFalse, reason: j.why('phone chat is off'));
      j.friend().join(j.relay.rooms.values.single.id);
      await j.wait(const Duration(seconds: 4));
      await j.select();
      await j.realTime();
      await j.wait(const Duration(seconds: 2));
      await j.down();
      expect(find.bySemanticsLabel('Phone chat'), findsNothing, reason: j.why('phone chat is off'));
    }, relay: true, settings: (s) => s.copyWith(phoneChat: false));
  });

  journey("a part-watched film's room offers Resume, from where it was left", (j) async {
    await j.right(); // Home's hero: Blade Runner, a third in — its Watch Together
    j.expectFocusOn('Watch Together');
    await j.select();
    expect(j.shows('From 33:20'), isTrue, reason: j.why('Resume says from when: ${j.screenTexts()}'));
    expect(j.shows('Start from the beginning'), isTrue);
  }, relay: true);

  group('Joining', () {
    journey("a friend's room shows on Home and in the rooms panel; Join lands in their lobby", (j) async {
      j.friend().host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await j.wait(const Duration(seconds: 20)); // the next directory poll
      await j.realTime();
      expect(j.shows("Riley's room is live"), isTrue, reason: j.why("Home's bar shows the live room"));

      await j.openFromRail('Watch Together');
      await j.realTime();
      j.expectFocusOn("Riley's room", because: 'the rooms panel focuses its first room');
      await j.select();
      await j.realTime();
      await j.wait(const Duration(seconds: 3));
      expect(j.shows('RILEY’S ROOM'), isTrue, reason: j.why("Riley's lobby should be open"));
      expect(j.shows('2 OF 8 SEATS'), isTrue, reason: j.why('Riley and you: two seats, Riley once'));
      expect(j.focusedRect()!.left, greaterThan(100), reason: j.why('the lobby claims focus; the rail must not keep it'));
    }, relay: true);

    journey("the host's Start plays your own copy, and the host's pause pauses you", (j) async {
      final riley = j.friend()..host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await joinRileysRoom(j);

      riley.start();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();
      expect(j.video.openedUris.last, contains('/Videos/m1/'), reason: j.why('your own Arrival, found by its IMDb id'));
      expect(j.videoPlaying, isTrue);

      riley.pressPause();
      await j.wait(const Duration(seconds: 2));
      expect(j.videoPlaying, isFalse, reason: j.why("Riley's pause pauses you"));
      riley.pressPlay();
      await j.wait(const Duration(seconds: 3));
      expect(j.videoPlaying, isTrue, reason: j.why("Riley's play resumes you"));
    }, relay: true);

    journey('joining late, while the host is already watching: straight into the player, in step with them', (j) async {
      final riley = j.friend()..host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      riley.start(atMs: 60000);
      await j.wait(const Duration(seconds: 20));
      await j.realTime();
      await j.openFromRail('Watch Together');
      await j.realTime();
      await j.select(); // Join
      await j.realTime();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();
      expect(j.shows('Start for everyone'), isFalse, reason: j.why('no lobby once the room is underway'));
      expect(j.video.openedUris.last, contains('/Videos/m1/'), reason: j.why('your own Arrival is playing'));
      await j.wait(const Duration(seconds: 10));
      expect(riley.phase, PlaybackPhase.playing, reason: j.why('the room plays on by itself once you have caught up'));
      expect(j.videoPlaying, isTrue);
      expect(j.relay.eventLog.any((e) => e.kind == 'playbackState' && e.phase == 'waitingForPeers'), isTrue,
          reason: j.why('the room held for you while you opened'));
    }, relay: true);

    journey('the host ends the room: you leave the player, and are told why', (j) async {
      final riley = j.friend()..host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await joinRileysRoom(j);
      riley.start();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();

      riley.endRoom();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();
      expect(j.shows('Seeking moves the whole room'), isFalse, reason: j.why('the player should close: the room is over'));
      expect(j.relay.eventLog.where((e) => e.kind == 'controlRequest'), isEmpty);
    }, relay: true);

    journey('the host walks away (their TV goes off): you are not told "In sync" with nobody', (j) async {
      final riley = j.friend()..host(title: 'Arrival', ids: ['imdb://tt00m1'], year: 1980);
      await joinRileysRoom(j);
      riley.start();
      await j.wait(const Duration(seconds: 3));
      await j.realTime();

      riley.leave();
      await j.wait(const Duration(seconds: 12));
      expect(j.shows('In sync'), isFalse, reason: j.why('the host has gone; "In sync" with nobody is wrong — on screen: ${j.screenTexts()}'));
    }, relay: true);
  });

  group('Starting a room (screen 09)', () {
    Future<void> toWatchTogether(Journey j) async {
      for (var i = 0; i < 4 && !j.focusedTexts().any((t) => t.contains('Watch Together')); i++) {
        await j.right();
      }
      j.expectFocusOn('Watch Together');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      expect(j.shows('Open the room'), isTrue, reason: j.why('the start dialog is open: ${j.screenTexts()}'));
    }

    journey("a film you've never started offers no Resume — there's nothing to resume", (j) async {
      await j.openFromRail('Movies');
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Arrival'); // never played
      await j.select();
      await j.wait(const Duration(seconds: 1));
      await toWatchTogether(j);
      expect(j.shows('Resume'), isFalse, reason: j.why('Arrival was never started: ${j.screenTexts()}'));
      expect(j.shows('Start from the beginning'), isFalse, reason: j.why('so there is nothing to choose between'));
    }, relay: true);

    journey('a film you are partway through offers Resume, from where you are', (j) async {
      await j.openFromRail('Movies');
      await j.wait(const Duration(seconds: 1));
      await j.right(); // Blade Runner, a third of the way in
      j.expectFocusOn('Blade Runner');
      await j.select();
      await j.wait(const Duration(seconds: 1));
      await toWatchTogether(j);
      expect(j.shows('Resume'), isTrue);
      expect(j.shows('From 33:20'), isTrue, reason: j.why(j.screenTexts().toString()));
      expect(j.shows('Start from the beginning'), isTrue);
    }, relay: true);

    journey("a show's next episode, never started: no Resume either", (j) async {
      await j.openFromRail('Shows');
      await j.right(); // Severance: next up is S1 E2, not started
      await j.select();
      await j.wait(const Duration(seconds: 1));
      j.expectFocusOn('Play S1 E2');
      await toWatchTogether(j);
      expect(j.shows('Resume'), isFalse, reason: j.why('S1 E2 was never started: ${j.screenTexts()}'));
    }, relay: true);
  });
}
