import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/playback/audio_tracks.dart';
import 'package:reelay/playback/playback_decision.dart';
import 'package:reelay/screens/player/player_menu_panel.dart';
import 'package:reelay/theme/phosphor_icons.dart';

const _subtitleOptions = [
  SubtitleOption(streamId: null, label: 'Off', requiresBurn: false),
  SubtitleOption(streamId: 1, label: 'English', requiresBurn: false),
  SubtitleOption(streamId: 2, label: 'Swedish (burn-in)', requiresBurn: true),
];

Future<void> _pump(
  WidgetTester tester, {
  List<SubtitleOption> subtitleOptions = _subtitleOptions,
  int? selectedSubtitleStreamId,
  ValueChanged<int?>? onSelectSubtitle,
  List<AudioOption> audioOptions = const [],
  ValueChanged<int>? onSelectAudio,
  int selectedBitrateKbps = 8000,
  ValueChanged<int>? onSelectBitrate,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          PlayerMenuPanel(
            subtitleOptions: subtitleOptions,
            selectedSubtitleStreamId: selectedSubtitleStreamId,
            onSelectSubtitle: onSelectSubtitle ?? (_) {},
            audioOptions: audioOptions,
            selectedAudioStreamId: audioOptions.isEmpty ? null : audioOptions.first.streamId,
            onSelectAudio: onSelectAudio ?? (_) {},
            selectedBitrateKbps: selectedBitrateKbps,
            onSelectBitrate: onSelectBitrate ?? (_) {},
            onClose: onClose ?? () {},
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Subtitles tab is shown by default, listing every real option', (tester) async {
    await _pump(tester);

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Swedish (burn-in)'), findsOneWidget);
    expect(find.text('2 Mbps (Low)'), findsNothing, reason: 'Quality tab is not active yet');
  });

  testWidgets('tapping a subtitle option invokes onSelectSubtitle with its streamId', (tester) async {
    int? selected = -1;
    await _pump(tester, onSelectSubtitle: (id) => selected = id);

    await tester.tap(find.text('English'));
    await tester.pump();

    expect(selected, 1);
  });

  testWidgets('switching to the Quality tab shows real bitrate presets', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Quality'));
    await tester.pump();

    expect(find.text('2 Mbps (Low)'), findsOneWidget);
    expect(find.text('8 Mbps (Good)'), findsOneWidget);
    expect(find.text('English'), findsNothing, reason: 'Subtitles tab is no longer active');
  });

  testWidgets('tapping a quality preset invokes onSelectBitrate with its kbps', (tester) async {
    int? selected;
    await _pump(tester, onSelectBitrate: (kbps) => selected = kbps);

    await tester.tap(find.text('Quality'));
    await tester.pump();
    await tester.tap(find.text('4 Mbps (Medium)'));
    await tester.pump();

    expect(selected, 4000);
  });

  testWidgets('the currently selected subtitle shows a check, unselected ones do not', (tester) async {
    await _pump(tester, selectedSubtitleStreamId: 1);

    expect(find.byIcon(PhosphorIconsFill.checkCircle), findsOneWidget);
  });

  testWidgets('no Audio tab for a file with a single audio track', (tester) async {
    await _pump(tester, audioOptions: const [AudioOption(streamId: 10, label: 'English (AC3 5.1)')]);
    expect(find.text('Audio'), findsNothing);
  });

  testWidgets('the Audio tab lists every track and picking one invokes onSelectAudio', (tester) async {
    int? picked;
    await _pump(
      tester,
      audioOptions: const [
        AudioOption(streamId: 10, label: 'English (TrueHD 7.1)'),
        AudioOption(streamId: 11, label: 'Commentary (AAC Stereo)'),
      ],
      onSelectAudio: (id) => picked = id,
    );

    await tester.tap(find.text('Audio'));
    await tester.pump();
    expect(find.text('English (TrueHD 7.1)'), findsOneWidget);

    await tester.tap(find.text('Commentary (AAC Stereo)'));
    await tester.pump();
    expect(picked, 11);
  });
}
