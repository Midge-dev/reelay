import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/player/player_controls_bar.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool isPlaying = false,
  int positionMs = 30000,
  int durationMs = 120000,
  bool subtitlesAvailable = true,
  bool chatAvailable = true,
  VoidCallback? onPlayPause,
  VoidCallback? onRewind,
  VoidCallback? onForward,
  VoidCallback? onOpenSubtitles,
  VoidCallback? onOpenBitrate,
  VoidCallback? onOpenChatQr,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PlayerControlsBar(
        isPlaying: isPlaying,
        positionMs: positionMs,
        durationMs: durationMs,
        subtitlesAvailable: subtitlesAvailable,
        chatAvailable: chatAvailable,
        onPlayPause: onPlayPause ?? () {},
        onRewind: onRewind ?? () {},
        onForward: onForward ?? () {},
        onOpenSubtitles: onOpenSubtitles ?? () {},
        onOpenBitrate: onOpenBitrate ?? () {},
        onOpenChatQr: onOpenChatQr ?? () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows position/duration formatted as timecodes', (tester) async {
    await _pump(tester, positionMs: 65000, durationMs: 3665000);
    expect(find.text('1:05 / 1:01:05'), findsOneWidget);
  });

  testWidgets('shows a pause icon while playing, play icon while paused', (tester) async {
    await _pump(tester, isPlaying: true);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('tapping play/pause invokes onPlayPause', (tester) async {
    var tapped = false;
    await _pump(tester, onPlayPause: () => tapped = true);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('tapping rewind invokes onRewind', (tester) async {
    var rewound = false;
    await _pump(tester, onRewind: () => rewound = true);

    await tester.tap(find.byIcon(Icons.replay_10));
    await tester.pump();

    expect(rewound, isTrue);
  });

  testWidgets('tapping forward invokes onForward', (tester) async {
    var forwarded = false;
    await _pump(tester, onForward: () => forwarded = true);

    await tester.tap(find.byIcon(Icons.forward_10));
    await tester.pump();

    expect(forwarded, isTrue);
  });

  testWidgets('subtitles button does not invoke onOpenSubtitles when disabled', (tester) async {
    var opened = false;
    await _pump(tester, subtitlesAvailable: false, onOpenSubtitles: () => opened = true);

    await tester.tap(find.byIcon(Icons.closed_caption));
    await tester.pump();

    expect(opened, isFalse);
  });

  testWidgets('subtitles button invokes onOpenSubtitles when available', (tester) async {
    var opened = false;
    await _pump(tester, onOpenSubtitles: () => opened = true);

    await tester.tap(find.byIcon(Icons.closed_caption));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('quality button invokes onOpenBitrate', (tester) async {
    var opened = false;
    await _pump(tester, onOpenBitrate: () => opened = true);

    await tester.tap(find.byIcon(Icons.high_quality));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('chat button does not invoke onOpenChatQr when unavailable', (tester) async {
    var opened = false;
    await _pump(tester, chatAvailable: false, onOpenChatQr: () => opened = true);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();

    expect(opened, isFalse);
  });
}
