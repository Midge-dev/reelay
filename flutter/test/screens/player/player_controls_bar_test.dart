import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/player/player_controls_bar.dart';
import 'package:reelay/theme/phosphor_icons.dart';

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
  VoidCallback? onCycleSubtitles,
  VoidCallback? onCycleBitrate,
  VoidCallback? onOpenChatQr,
  VoidCallback? onOpenMenu,
  FocusNode? progressFocusNode,
  FocusNode? playPauseFocusNode,
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
        subtitleLabel: 'English',
        qualityLabel: '20 Mbps',
        progressFocusNode: progressFocusNode ?? FocusNode(),
        rewindFocusNode: FocusNode(),
        playPauseFocusNode: playPauseFocusNode ?? FocusNode(),
        forwardFocusNode: FocusNode(),
        subtitlesFocusNode: FocusNode(),
        bitrateFocusNode: FocusNode(),
        chatFocusNode: FocusNode(),
        chatAvailable: chatAvailable,
        onPlayPause: onPlayPause ?? () {},
        onRewind: onRewind ?? () {},
        onForward: onForward ?? () {},
        onSeekKeyEvent: (_) => KeyEventResult.ignored,
        onCycleSubtitles: onCycleSubtitles ?? () {},
        onCycleBitrate: onCycleBitrate ?? () {},
        onOpenChatQr: onOpenChatQr ?? () {},
        menuFocusNode: FocusNode(),
        onOpenMenu: onOpenMenu ?? () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows position and duration as timecodes either side of the scrubber', (tester) async {
    await _pump(tester, positionMs: 65000, durationMs: 3665000);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('1:01:05'), findsOneWidget);
  });

  testWidgets('shows a pause icon while playing, play icon while paused', (tester) async {
    await _pump(tester, isPlaying: true);
    expect(find.byIcon(PhosphorIconsFill.pause), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.play), findsNothing);
  });

  testWidgets('tapping play/pause invokes onPlayPause', (tester) async {
    var tapped = false;
    await _pump(tester, onPlayPause: () => tapped = true);

    await tester.tap(find.byIcon(PhosphorIconsFill.play));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('tapping rewind invokes onRewind', (tester) async {
    var rewound = false;
    await _pump(tester, onRewind: () => rewound = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.rewind));
    await tester.pump();

    expect(rewound, isTrue);
  });

  testWidgets('tapping forward invokes onForward', (tester) async {
    var forwarded = false;
    await _pump(tester, onForward: () => forwarded = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.fastForward));
    await tester.pump();

    expect(forwarded, isTrue);
  });

  testWidgets('subtitles button does not invoke onCycleSubtitles when disabled', (tester) async {
    var opened = false;
    await _pump(tester, subtitlesAvailable: false, onCycleSubtitles: () => opened = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.closedCaptioning));
    await tester.pump();

    expect(opened, isFalse);
  });

  testWidgets('subtitles button invokes onCycleSubtitles when available', (tester) async {
    var opened = false;
    await _pump(tester, onCycleSubtitles: () => opened = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.closedCaptioning));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('quality button invokes onCycleBitrate', (tester) async {
    var opened = false;
    await _pump(tester, onCycleBitrate: () => opened = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.monitor));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('no chat button outside a Watch Together session', (tester) async {
    await _pump(tester, chatAvailable: false);

    expect(find.byIcon(PhosphorIconsRegular.chatCircleText), findsNothing);
  });

  testWidgets('subtitle and quality pills state their current values', (tester) async {
    await _pump(tester);

    expect(find.text('English'), findsOneWidget);
    expect(find.text('20 Mbps'), findsOneWidget);
  });

  testWidgets('menu button invokes onOpenMenu', (tester) async {
    var opened = false;
    await _pump(tester, onOpenMenu: () => opened = true);

    await tester.tap(find.byIcon(PhosphorIconsRegular.gear));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('Up from the buttons focuses the scrubber, which shows the seek time', (tester) async {
    final progress = FocusNode();
    final playPause = FocusNode();
    addTearDown(progress.dispose);
    addTearDown(playPause.dispose);
    await _pump(tester, progressFocusNode: progress, playPauseFocusNode: playPause);

    playPause.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(progress.hasFocus, isTrue);
    // Position 0:30 is shown beside the scrubber and again in the bubble.
    expect(find.text('0:30'), findsNWidgets(2));
  });
}
