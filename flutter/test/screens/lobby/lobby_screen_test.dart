import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/screens/lobby/lobby_screen.dart';
import 'package:reelay/sync/relay_client.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _detail = PlexMovieDetail(ratingKey: '1', title: 'Arrival');
const _detailWithProgress = PlexMovieDetail(ratingKey: '1', title: 'Arrival', viewOffset: 500);

// RelayClient is a concrete class with no test seam for injecting live
// socket frames without a fake WebSocket server — these tests exercise
// everything reachable from its default (never-connected) state:
// connectionState = disconnected, seatIndex = null (not host), roomId =
// null. Presence/roster wiring itself is straightforward and reviewed by
// eye; RelayEvent/RelayClient's own protocol logic is unit-tested in
// test/sync/.
RelayClient _relay() => RelayClient('wss://relay.example.com', const RelayIdentity(peerId: 'me'));

Future<void> _pump(
  WidgetTester tester, {
  PlexMovieDetail detail = _detail,
  RelayClient? relay,
  VoidCallback? onBack,
  ValueChanged<bool>? onStart,
  VoidCallback? onHostOnAnother,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = relay ?? _relay();
  addTearDown(client.dispose);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: LobbyScreen(
        server: _server,
        detail: detail,
        localUsername: 'Sean',
        hostName: 'Alex',
        relayNickname: 'Home Relay',
        relay: client,
        onHostOnAnother: onHostOnAnother,
        onStart: onStart ?? (_) {},
        onBack: onBack ?? () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the movie title and relay nickname', (tester) async {
    await _pump(tester);

    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Home Relay'), findsOneWidget);
  });

  testWidgets('shows a host card and, since we are not host yet, our own pinned card', (tester) async {
    await _pump(tester);

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('host'), findsOneWidget);
    expect(find.text('Sean'), findsOneWidget);
  });

  testWidgets('tapping Start invokes onStart(false)', (tester) async {
    bool? restarted;
    await _pump(tester, onStart: (r) => restarted = r);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(restarted, isFalse);
  });

  testWidgets('no restart-from-beginning button when not host', (tester) async {
    await _pump(tester, detail: _detailWithProgress);

    expect(find.byIcon(Icons.replay), findsNothing);
  });

  testWidgets('tapping "Chat QR code" opens the modal', (tester) async {
    await _pump(tester);

    expect(find.text('Join the chat'), findsNothing);

    await tester.tap(find.text('Chat QR code'));
    await tester.pump();

    expect(find.text('Join the chat'), findsOneWidget);
  });

  testWidgets('the chat modal shows "still connecting" before a room id is known', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Chat QR code'));
    await tester.pump();

    expect(find.text('Still connecting to the room — try again in a moment.'), findsOneWidget);
  });

  testWidgets('closing the chat modal dismisses it', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Chat QR code'));
    await tester.pump();
    expect(find.text('Join the chat'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(find.text('Join the chat'), findsNothing);
  });

  // PopScope only registers a pop entry once it finds an ancestor
  // ModalRoute, so — unlike every other test here — back-handling needs a
  // real WidgetsApp (giving it a Navigator/route, same pageRouteBuilder as
  // lib/main.dart) rather than a bare Directionality, plus WidgetsBinding's
  // own @visibleForTesting handlePopRoute() to simulate the OS back
  // button/gesture.
  group('back handling (needs a real Navigator route)', () {
    Widget testApp(VoidCallback onBack, RelayClient client) => WidgetsApp(
          color: const Color(0xFF000000),
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          ),
          home: LobbyScreen(
            server: _server,
            detail: _detail,
            localUsername: 'Sean',
            hostName: 'Alex',
            relayNickname: 'Home Relay',
            relay: client,
            onStart: (_) {},
            onBack: onBack,
          ),
        );

    testWidgets('back with the chat modal open closes the modal, not the screen', (tester) async {
      var wentBack = false;
      final client = _relay();
      addTearDown(client.dispose);

      await tester.pumpWidget(testApp(() => wentBack = true, client));
      await tester.pump();

      await tester.tap(find.text('Chat QR code'));
      await tester.pump();
      expect(find.text('Join the chat'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Join the chat'), findsNothing);
      expect(wentBack, isFalse);
    });

    testWidgets('back with no modal open leaves the lobby', (tester) async {
      var wentBack = false;
      final client = _relay();
      addTearDown(client.dispose);

      await tester.pumpWidget(testApp(() => wentBack = true, client));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(wentBack, isTrue);
    });
  });
}
