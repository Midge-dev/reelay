import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'sim/sim_player.dart';
import 'sim/sim_relay.dart';
import 'sim/sim_room.dart';
import 'sim/trace_replay.dart';

/// Real sessions as tests: every folder under test/sync/traces/ holds the
/// `.jsonl` trace(s) one room left behind (see test/sync/traces/README.md),
/// and is replayed through the room simulation — it has to settle.
void main() {
  String jsonl(RoomResult r, String device) => r.traces[device]!.entries.map(jsonEncode).join('\n');

  const recorded = Scenario('recorded', devices: [
    DeviceSpec('host', player: PlayerProfile.directPlay, startMs: 1200000),
    DeviceSpec('shield', player: PlayerProfile.remoteTranscode, link: LinkProfile.far, startMs: 1191000, clockSkewMs: -90000),
  ], actions: [
    SeekBy(15000, 'shield', -30000),
    TogglePlay(30000, 'host'),
    TogglePlay(38000, 'host'),
    Stall(50000, 'shield', 4000),
  ]);

  group('a trace read back', () {
    late RoomResult original;
    setUpAll(() => original = runRoom(recorded));

    test('recovers the room it came from', () {
      final s = scenarioFromTraces('round trip', [
        DeviceTrace.parse('host', jsonl(original, 'host')),
        DeviceTrace.parse('shield', jsonl(original, 'shield')),
      ]);
      final why = s.toString();
      expect(s.devices.map((d) => d.name), ['host', 'shield'], reason: why);
      final shield = s.devices[1];
      expect(shield.player.seekLatencyMinMs, greaterThanOrEqualTo(2000), reason: why);
      expect(shield.player.seekLatencyMaxMs, lessThanOrEqualTo(3500), reason: why);
      expect(shield.clockSkewMs, closeTo(-90000, 400), reason: why);
      expect(shield.startMs, 1191000, reason: why);

      final kinds = s.actions.map((a) => '${a.runtimeType}@${a.device}').toList();
      expect(kinds, ['SeekTo@shield', 'EnsurePaused@host', 'EnsurePlaying@host', 'Stall@shield'], reason: why);
      expect(s.actions[0].atMs, closeTo(15000, 400), reason: why);
      expect(s.actions[1].atMs, closeTo(30000, 400), reason: why);
      // A trace only shows how long the player buffered; a seek the engine
      // made mid-stall runs straight on, so the spell can read longer.
      expect((s.actions[3] as Stall).ms, inInclusiveRange(3900, 8000), reason: why);
    });

    test('replays to a room that settles, from both sides or just one', () {
      for (final traces in [
        [DeviceTrace.parse('host', jsonl(original, 'host')), DeviceTrace.parse('shield', jsonl(original, 'shield'))],
        [DeviceTrace.parse('shield', jsonl(original, 'shield'))],
        [DeviceTrace.parse('host', jsonl(original, 'host'))],
      ]) {
        final r = runRoom(scenarioFromTraces('replay', traces));
        expect(r.timeToSyncMs, isNotNull, reason: r.describe());
        expect(r.timeToSyncMs, lessThanOrEqualTo(r.scenario.settleMs), reason: r.describe());
      }
    });
  });

  final dir = Directory('test/sync/traces');
  final sessions = dir.existsSync()
      ? (dir.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path)))
      : <Directory>[];
  for (final session in sessions) {
    final files = session.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList();
    if (files.isEmpty) continue;
    final name = session.uri.pathSegments.where((p) => p.isNotEmpty).last;
    test('recorded session "$name" settles', () {
      final traces = [
        for (final f in files)
          DeviceTrace.parse(f.uri.pathSegments.last.replaceAll('.jsonl', ''), f.readAsStringSync()),
      ];
      final r = runRoom(scenarioFromTraces(name, traces));
      expect(r.timeToSyncMs, isNotNull, reason: r.describe());
      expect(r.timeToSyncMs, lessThanOrEqualTo(r.scenario.settleMs), reason: r.describe());
    });
  }
}
