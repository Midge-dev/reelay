import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/home/watch_together_row.dart';
import 'package:reelay/sync/relay_protocol.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _relay = RelayEntry(id: 'r1', nickname: 'Home Relay', url: 'wss://relay.example.com');

RelayRoomSummary _room({int occupants = 1, int maxSeats = 4, String roomId = 'room-1'}) => RelayRoomSummary(
      roomId: roomId,
      title: 'Arrival',
      hostName: 'Sean',
      occupants: occupants,
      maxSeats: maxSeats,
    );

void main() {
  group('RoomCard', () {
    Future<void> pump(
      WidgetTester tester, {
      required MergedRoom merged,
      bool isMine = false,
      bool isHosted = false,
      VoidCallback? onClick,
      Future<bool> Function(MergedRoom)? onEndSession,
    }) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RoomCard(
              server: _server,
              merged: merged,
              isMine: isMine,
              isHosted: isHosted,
              onClick: onClick ?? () {},
              onEndSession: onEndSession ?? (_) async => true,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the room title, host, and occupancy', (tester) async {
      final merged = MergedRoom(_relay, _room(occupants: 2, maxSeats: 4));
      await pump(tester, merged: merged);

      expect(find.text('Arrival'), findsOneWidget);
      expect(find.text('Sean hosting'), findsOneWidget);
      expect(find.text('2 of 4 watching'), findsOneWidget);
    });

    testWidgets('shows the relay nickname', (tester) async {
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged);

      expect(find.text('Available on Home Relay'), findsOneWidget);
    });

    testWidgets('tapping Join invokes onClick', (tester) async {
      var clicked = false;
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged, onClick: () => clicked = true);

      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(clicked, isTrue);
    });

    testWidgets('a full room shows a disabled Full button instead of Join', (tester) async {
      final merged = MergedRoom(_relay, _room(occupants: 4, maxSeats: 4));
      await pump(tester, merged: merged);

      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('the room you are already in shows Rejoin instead of Join', (tester) async {
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged, isMine: true);

      expect(find.text('Rejoin'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('a hosted room shows an End session button', (tester) async {
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged, isHosted: true, isMine: true);

      expect(find.text('End session'), findsOneWidget);
      expect(find.text("You're hosting"), findsOneWidget);
    });

    testWidgets('a non-hosted room has no End session button', (tester) async {
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged);

      expect(find.text('End session'), findsNothing);
    });

    testWidgets('tapping End session invokes onEndSession', (tester) async {
      MergedRoom? ended;
      final merged = MergedRoom(_relay, _room());
      await pump(
        tester,
        merged: merged,
        isHosted: true,
        isMine: true,
        onEndSession: (r) async {
          ended = r;
          return true;
        },
      );

      await tester.tap(find.text('End session'));
      await tester.pump();

      expect(ended, same(merged));
    });

    testWidgets('a failed end-session shows "Can\'t reach relay" instead of the buttons', (tester) async {
      final merged = MergedRoom(_relay, _room());
      await pump(tester, merged: merged, isHosted: true, isMine: true, onEndSession: (_) async => false);

      await tester.tap(find.text('End session'));
      await tester.pump();

      expect(find.text("Can't reach relay"), findsOneWidget);
      expect(find.text('End session'), findsNothing);

      // Drain the 4s auto-reset timer so it doesn't outlive the test.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('WatchTogetherRow', () {
    testWidgets('renders nothing when there are no live rooms', (tester) async {
      final rowFocus = FocusNode();
      addTearDown(rowFocus.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WatchTogetherRow(
            server: _server,
            rooms: const [],
            onEndSession: (_) async => true,
            onSelectRoom: (_) {},
            rowAnchorFocusNode: rowFocus,
            scrollController: scrollController,
          ),
        ),
      );

      expect(find.text('Watch Together'), findsNothing);
    });

    testWidgets('shows the room count and relay count in the header', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rowFocus = FocusNode();
      addTearDown(rowFocus.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WatchTogetherRow(
            server: _server,
            rooms: [MergedRoom(_relay, _room(roomId: 'a')), MergedRoom(_relay, _room(roomId: 'b'))],
            onEndSession: (_) async => true,
            onSelectRoom: (_) {},
            rowAnchorFocusNode: rowFocus,
            scrollController: scrollController,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Watch Together'), findsOneWidget);
      expect(find.text('2 rooms live · 1 relay'), findsOneWidget);
    });

    testWidgets('tapping a room card invokes onSelectRoom with that room', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rowFocus = FocusNode();
      addTearDown(rowFocus.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      MergedRoom? selected;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WatchTogetherRow(
            server: _server,
            rooms: [MergedRoom(_relay, _room())],
            onEndSession: (_) async => true,
            onSelectRoom: (r) => selected = r,
            rowAnchorFocusNode: rowFocus,
            scrollController: scrollController,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(selected?.room.roomId, 'room-1');
    });
  });
}
