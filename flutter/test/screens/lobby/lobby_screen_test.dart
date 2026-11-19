import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/screens/lobby/lobby_screen.dart';
import 'package:reelay/sync/relay_client.dart';
import 'package:reelay/theme/phosphor_icons.dart';

const _server = MediaServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _detail = MediaDetail(id: '1', title: 'Arrival');
const _detailWithProgress = MediaDetail(id: '1', title: 'Arrival', viewOffset: 500);

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
  MediaDetail detail = _detail,
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
    // Never connected in tests, so the header line is still connecting.
    expect(find.text('Connecting to Home Relay…'), findsOneWidget);
  });

  testWidgets('screen 10 header: whose room and how many seats are taken', (tester) async {
    await _pump(tester);

    expect(find.text('ALEX’S ROOM · 2 OF 8 SEATS'), findsOneWidget);
  });

  testWidgets('empty seats are drawn, not implied — five circles in all', (tester) async {
    await _pump(tester);

    // Host + us, so three drawn empty seats.
    expect(find.text('Empty seat'), findsNWidgets(3));
  });

  testWidgets('shows a host card and, since we are not host yet, our own pinned card', (tester) async {
    await _pump(tester);

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Sean'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('tapping Start invokes onStart(false)', (tester) async {
    bool? restarted;
    await _pump(tester, onStart: (r) => restarted = r);

    await tester.tap(find.text('Start for everyone'));
    await tester.pump();

    expect(restarted, isFalse);
  });

  testWidgets('no restart-from-beginning button when not host', (tester) async {
    await _pump(tester, detail: _detailWithProgress);

    expect(find.byIcon(PhosphorIconsRegular.arrowCounterClockwise), findsNothing);
  });

  testWidgets('no QR before the room has an id (still connecting)', (tester) async {
    await _pump(tester);

    expect(find.text('Scan to chat'), findsNothing);
    expect(find.text('Chat QR'), findsNothing, reason: 'the QR is shown, not behind a button');
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

    testWidgets('back leaves the lobby', (tester) async {
      var wentBack = false;
      final client = _relay();
      addTearDown(client.dispose);

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(testApp(() => wentBack = true, client));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(wentBack, isTrue);
    });
  });
}
