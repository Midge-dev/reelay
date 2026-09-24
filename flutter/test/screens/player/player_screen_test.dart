import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/screens/player/player_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../playback/fake_video_player_platform.dart';

const _server = PlexServer(name: 'Loft', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _detail = PlexMovieDetail(
  ratingKey: '1',
  title: 'Arrival',
  viewOffset: 60000,
  media: [
    PlexMedia(parts: [PlexPart(id: 1, key: '/library/parts/1/file.mkv')]),
  ],
);

Future<List<(String, int)>> _pumpPlayer(WidgetTester tester, FakeVideoPlayerPlatform fake) async {
  VideoPlayerPlatform.instance = fake;
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final failures = <(String, int)>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PlayerScreen(
        server: _server,
        detail: _detail,
        clientIdentifier: 'client-1',
        settings: const AppSettings(),
        onBitrateChanged: (_) {},
        onExit: () {},
        onFailed: (reason, positionMs) => failures.add((reason, positionMs)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return failures;
}

// Unmount, then let any leftover one-shot timers (controls auto-hide, the
// stopped report's HTTP timeout) run out inside the test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  testWidgets('a stream the TV cannot open reports a failure, with where to resume', (tester) async {
    final failures = await _pumpPlayer(tester, FakeVideoPlayerPlatform(failInit: true));

    expect(failures, [("Loft sent a stream this TV couldn't open", 60000)]);
    await _unmount(tester);
  });

  testWidgets('a stream that errors mid-play reports one failure', (tester) async {
    final fake = FakeVideoPlayerPlatform();
    final failures = await _pumpPlayer(tester, fake);
    expect(failures, isEmpty);

    fake.emitError(0);
    await tester.pump();
    await tester.pump();

    expect(failures, hasLength(1));
    expect(failures.single.$1, 'The stream from Loft stopped partway through');
    await _unmount(tester);
  });
}
