import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/playback/display_mode.dart';

const _film = PlexPart(
  id: 1,
  key: '/library/parts/1/file.mkv',
  streams: [PlexStream(id: 1, streamType: 1, frameRate: 23.976, width: 1920, height: 800)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('reelay/display'),
      (call) async {
        calls.add(call);
        return call.method == 'matchFrameRate' ? true : null;
      },
    );
  });

  test('asks the TV for the video stream\'s frame rate and size', () async {
    await DisplayMode.matchFrameRate(_film, owner: Object());
    expect(calls.single.method, 'matchFrameRate');
    expect(calls.single.arguments, {'fps': 23.976, 'width': 1920, 'height': 800});
  });

  test('a stream with no frame rate hands the display back instead', () async {
    await DisplayMode.matchFrameRate(const PlexPart(id: 2, key: '/x', streams: []), owner: Object());
    expect(calls.single.method, 'clearFrameRate');
  });

  test('an older player\'s clear does not undo a newer player\'s request', () async {
    final oldPlayer = Object();
    final newPlayer = Object();
    await DisplayMode.matchFrameRate(_film, owner: oldPlayer);
    await DisplayMode.matchFrameRate(_film, owner: newPlayer);
    calls.clear();

    await DisplayMode.clear(owner: oldPlayer);
    expect(calls, isEmpty);

    await DisplayMode.clear(owner: newPlayer);
    expect(calls.single.method, 'clearFrameRate');
  });

  test('without the platform side (not Android), it quietly does nothing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('reelay/display'),
      null,
    );
    await expectLater(DisplayMode.matchFrameRate(_film, owner: Object()), completes);
    await expectLater(DisplayMode.clear(owner: Object()), completes);
  });
}
