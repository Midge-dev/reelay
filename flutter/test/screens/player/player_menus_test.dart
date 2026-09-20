import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/playback/playback_decision.dart';
import 'package:reelay/screens/player/player_menus.dart';

Future<void> _pumpSubtitles(
  WidgetTester tester, {
  required List<SubtitleOption> options,
  int? selectedStreamId,
  ValueChanged<SubtitleOption>? onSelect,
  VoidCallback? onDismiss,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SubtitleMenu(
        options: options,
        selectedStreamId: selectedStreamId,
        onSelect: onSelect ?? (_) {},
        onDismiss: onDismiss ?? () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpBitrate(
  WidgetTester tester, {
  required int selectedKbps,
  ValueChanged<int>? onSelect,
  VoidCallback? onDismiss,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: BitrateMenu(selectedKbps: selectedKbps, onSelect: onSelect ?? (_) {}, onDismiss: onDismiss ?? () {}),
    ),
  );
  await tester.pump();
}

void main() {
  group('SubtitleMenu', () {
    const options = [
      SubtitleOption(streamId: null, label: 'Off', requiresBurn: false),
      SubtitleOption(streamId: 1, label: 'English', requiresBurn: false),
      SubtitleOption(streamId: 2, label: 'Spanish (transcode)', requiresBurn: true),
    ];

    testWidgets('lists every option label', (tester) async {
      await _pumpSubtitles(tester, options: options);

      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Spanish (transcode)'), findsOneWidget);
    });

    testWidgets('tapping an option invokes onSelect with that option', (tester) async {
      SubtitleOption? selected;
      await _pumpSubtitles(tester, options: options, onSelect: (o) => selected = o);

      await tester.tap(find.text('English'));
      await tester.pump();

      expect(selected?.streamId, 1);
    });
  });

  group('BitrateMenu', () {
    testWidgets('lists every bitrate preset label', (tester) async {
      await _pumpBitrate(tester, selectedKbps: AppSettings.defaultMaxBitrateKbps);

      for (final preset in AppSettings.bitratePresets) {
        expect(find.text(preset.label), findsOneWidget);
      }
    });

    testWidgets('tapping a preset invokes onSelect with its kbps', (tester) async {
      int? selectedKbps;
      await _pumpBitrate(tester, selectedKbps: AppSettings.defaultMaxBitrateKbps, onSelect: (kbps) => selectedKbps = kbps);

      final lowPreset = AppSettings.bitratePresets.first;
      await tester.tap(find.text(lowPreset.label));
      await tester.pump();

      expect(selectedKbps, lowPreset.kbps);
    });
  });
}
