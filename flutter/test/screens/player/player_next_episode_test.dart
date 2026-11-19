import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/plex/plex_client.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/screens/player/player_screen.dart';
import 'package:reelay/sync/episode_switch.dart';
import 'package:reelay/sync/relay_client.dart';
import 'package:reelay/sync/relay_protocol.dart';
import 'package:reelay/sync/sync_trace_file.dart';
import 'package:reelay/theme/scale.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../playback/fake_video_player_platform.dart';

class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
  @override
  void close({bool force = false}) {}
}

/// A room seat: [seat] 0 hosts. What the app sends is kept in [sent]; a
/// test plays the other side with [receive].
class _Room extends RelayClient {
  _Room({required this.seat}) : super('wss://relay.example.com', const RelayIdentity(peerId: 'me'));
  final int seat;
  final sent = <RelayEvent>[];
  final _events = StreamController<RelayEvent>.broadcast(sync: true);

  void receive(RelayEvent e) => _events.add(e);

  @override
  Stream<RelayEvent> get events => _events.stream;
  @override
  int? get seatIndexValue => seat;
  @override
  Stream<int?> get seatIndex => Stream.value(seat);
  @override
  Stream<ConnectionState> get connectionState => Stream.value(ConnectionState.connected);
  @override
  ConnectionState get connectionStateValue => ConnectionState.connected;
  @override
  Stream<String?> get roomId => Stream.value('room-1');
  @override
  void send(RelayEvent event) => sent.add(event);
}

const _server = MediaServer(name: 'Loft', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok', id: 'loft');
const _episode = MediaDetail(
  id: 'e2',
  kind: MediaKind.episode,
  title: 'Half Loop',
  grandparentTitle: 'Severance',
  parentIndex: 1,
  index: 2,
  showId: 'sev',
  media: [
    MediaVersion(parts: [MediaPart(id: '1', key: '/library/parts/1/file.mkv')]),
  ],
);
const _next = MediaItem(id: 'e3', kind: MediaKind.episode, title: 'In Perpetuity', index: 3, parentIndex: 1);

class _Played {
  final nexts = <(String, List<String>)>[];
  final follows = <EpisodeSwitch>[];
}

Future<(_Played, FakeVideoPlayerPlatform)> _open(
  WidgetTester tester, {
  MediaDetail detail = _episode,
  MediaItem? next = _next,
  _Room? room,
  List<String> roomPeers = const [],
  double? shieldUiScale,
}) async {
  final fake = FakeVideoPlayerPlatform(initialDuration: const Duration(minutes: 50));
  VideoPlayerPlatform.instance = fake;
  tester.view.physicalSize = shieldUiScale == null ? const Size(1920, 1080) : const Size(960, 540);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final played = _Played();
  await tester.pumpWidget(
    WidgetsApp(
      builder: shieldUiScale == null
          ? null
          : (context, child) => AppScale(factor: 540 / 1080 * shieldUiScale, child: child!),
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (c, _, _) => builder(c)),
      home: PlayerScreen(
        client: PlexClient(_server, 'client-1', client: Dio()..httpClientAdapter = _Offline()),
        detail: detail,
        relay: room,
        settings: const AppSettings(),
        onBitrateChanged: (_) {},
        onExit: () {},
        onFailed: (_, _) {},
        loadNextEpisode: detail.kind == MediaKind.episode ? () async => next : null,
        onPlayNext: (n, peers) => played.nexts.add((n.id, peers)),
        onFollowEpisode: played.follows.add,
        roomPeers: roomPeers,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return (played, fake);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

const _askNext = RelayEvent(kind: 'controlRequest', fromPeerId: 'guest-1', requestKind: EpisodeSwitch.nextRequestKind);

void main() {
  setUp(() => SyncTraceFile.enabled = false);
  tearDown(() => SyncTraceFile.enabled = true);

  testWidgets('an episode with another after it has Next episode, right after Forward', (tester) async {
    final (played, _) = await _open(tester);
    expect(find.bySemanticsLabel('Next episode'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowRight, times: 2); // Forward, Next episode
    await _press(tester, LogicalKeyboardKey.select);
    expect(played.nexts.map((n) => n.$1), ['e3']);
    await _close(tester);
  });

  testWidgets('no button for the last episode, or a film', (tester) async {
    await _open(tester, next: null);
    expect(find.bySemanticsLabel('Next episode'), findsNothing);
    await _close(tester);

    await _open(
      tester,
      detail: const MediaDetail(
        id: 'f',
        kind: MediaKind.movie,
        title: 'Arrival',
        media: [
          MediaVersion(parts: [MediaPart(id: '2', key: '/library/parts/2/file.mkv')]),
        ],
      ),
    );
    expect(find.bySemanticsLabel('Next episode'), findsNothing);
    await _close(tester);
  });

  testWidgets('pressed twice, it still moves on once', (tester) async {
    final (played, _) = await _open(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    await _press(tester, LogicalKeyboardKey.select, times: 2);
    expect(played.nexts, hasLength(1));
    await _close(tester);
  });

  for (final scale in [1.0, 1.3, 1.5]) {
    testWidgets('in a room, the controls row with Next episode fits the Shield at ${(scale * 100).round()}%', (tester) async {
      await _open(tester, room: _Room(seat: 0), shieldUiScale: scale);
      expect(find.bySemanticsLabel('Next episode'), findsOneWidget);
      expect(find.text('Seeking moves the whole room'), findsOneWidget);
      expect(tester.takeException(), isNull); // an overflow would be reported here
      await _close(tester);
    });
  }

  group('in a room', () {
    testWidgets("a guest's Next asks the host, and plays nothing itself", (tester) async {
      final room = _Room(seat: 1);
      final (played, _) = await _open(tester, room: room);
      await _press(tester, LogicalKeyboardKey.arrowRight, times: 2);
      await _press(tester, LogicalKeyboardKey.select);

      expect(room.sent.where((e) => e.kind == 'controlRequest' && e.requestKind == 'next'), hasLength(1));
      expect(played.nexts, isEmpty);
      await _close(tester);
    });

    testWidgets('the host moves the room on when a guest asks — once, however many ask', (tester) async {
      final room = _Room(seat: 0);
      final (played, _) = await _open(tester, room: room, roomPeers: const ['guest-1']);
      room.receive(_askNext);
      room.receive(_askNext);
      await tester.pump(const Duration(milliseconds: 50));

      expect(played.nexts, hasLength(1));
      expect(played.nexts.single.$1, 'e3');
      expect(played.nexts.single.$2, contains('guest-1'), reason: 'the new stream waits for the room');
      await _close(tester);
    });

    testWidgets("a guest follows the host's switch: its own sync stops first, then it moves on", (tester) async {
      final room = _Room(seat: 1);
      final (played, fake) = await _open(tester, room: room);
      final to = EpisodeSwitch.to(
        const MediaDetail(id: 'h3', kind: MediaKind.episode, title: 'In Perpetuity', parentIndex: 1, index: 3),
        const MediaServer(name: 'Attic', baseUrl: 'http://attic', accessToken: 't', id: 'attic'),
        showTitle: 'Severance',
      );
      room.sent.clear();
      room.receive(to.toEvent('host'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(played.follows.map((f) => (f.title, f.seasonIndex, f.episodeIndex)), [('Severance · S1E3', 1, 3)]);
      expect(
        room.sent.where((e) => e.kind == 'peerStatus' && e.ready == false),
        isNotEmpty,
        reason: 'its old session tells the host it is no longer ready, so the host waits',
      );
      expect(fake.calls.last, 'pause');
      expect(played.nexts, isEmpty);
      await _close(tester);
    });

    testWidgets("a host ignores another host's switch; a guest ignores requests", (tester) async {
      final asHost = _Room(seat: 0);
      final (hostPlayed, _) = await _open(tester, room: asHost);
      asHost.receive(EpisodeSwitch.to(_episode, _server, showTitle: 'Severance').toEvent('someone'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(hostPlayed.follows, isEmpty);
      await _close(tester);

      final asGuest = _Room(seat: 1);
      final (guestPlayed, _) = await _open(tester, room: asGuest);
      asGuest.receive(_askNext);
      await tester.pump(const Duration(milliseconds: 50));
      expect(guestPlayed.nexts, isEmpty);
      await _close(tester);
    });
  });
}
