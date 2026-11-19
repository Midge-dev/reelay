import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'sim/sim_player.dart';
import 'sim/sim_relay.dart';
import 'sim/sim_room.dart';

/// Random rooms: random players, links, clocks, resume points and a random
/// run of seeks, scrubs, pauses and stalls — then the room must settle.
/// Everything derives from the seed, so a failure prints a scenario that
/// replays exactly:
///
///     SYNC_FUZZ_SEED=1234 flutter test test/sync/room_fuzz_test.dart
///
/// SYNC_FUZZ_RUNS sets how many rooms (default 150; try 2000 before a
/// release).
void main() {
  final env = Platform.environment;
  final onlySeed = int.tryParse(env['SYNC_FUZZ_SEED'] ?? '');
  final runs = int.tryParse(env['SYNC_FUZZ_RUNS'] ?? '') ?? 150;
  final seeds = onlySeed != null ? [onlySeed] : [for (var i = 1; i <= runs; i++) i];

  test('${seeds.length} random rooms all settle', () {
    final failures = <String>[];
    for (final seed in seeds) {
      final scenario = randomScenario(seed);
      final r = runRoom(scenario);
      final problem = _problem(r);
      if (problem != null) failures.add('── seed $seed: $problem\n${r.describe(traceLines: onlySeed != null ? 300 : 40)}');
    }
    if (failures.isEmpty) return;
    final summary = failures.map((f) => f.split('\n').first).join('\n');
    fail('${failures.length} of ${seeds.length} rooms failed:\n$summary\n\nfirst one in full:\n${failures.first}');
  });
}

String? _problem(RoomResult r) {
  final t = r.timeToSyncMs;
  if (t == null) return 'never settled';
  if (t > r.scenario.settleMs) return 'took ${t}ms to settle';
  if (!r.endsPlaying) return 'ended paused';
  // Each scrub step is a seek of its own that every device has to follow.
  final actions = r.scenario.devices.length +
      r.scenario.actions.fold<int>(0, (n, a) => n + (a is Scrub ? a.steps : 1));
  if (r.totalSyncSeeks > 4 * actions) return '${r.totalSyncSeeks} corrective seeks for $actions actions';
  return null;
}

Scenario randomScenario(int seed) {
  final rng = Random(seed);
  int between(int lo, int hi) => lo + rng.nextInt(hi - lo + 1);

  PlayerProfile player() {
    final lo = [0, 150, 400, 1200, 2500, 4000][rng.nextInt(6)];
    return PlayerProfile(seekLatencyMinMs: lo, seekLatencyMaxMs: lo + between(0, 1500));
  }

  LinkProfile link() => LinkProfile(upMs: between(10, 250), downMs: between(10, 250), jitterMs: between(0, 150));

  const hostStart = 1800000;
  final guests = between(1, 3);
  final devices = [
    DeviceSpec('host', player: player(), link: link(), startMs: hostStart),
    for (var i = 1; i <= guests; i++)
      DeviceSpec(
        'guest$i',
        player: player(),
        link: link(),
        startMs: hostStart + (rng.nextBool() ? 0 : between(-60000, 60000)),
        clockSkewMs: between(-300000, 300000),
        joinAtMs: rng.nextInt(3) == 0 ? between(1000, 15000) : 0,
      ),
  ];
  final names = devices.map((d) => d.name).toList();

  final actions = <SimAction>[];
  var at = between(12000, 20000);
  for (var n = between(3, 8); n > 0; n--) {
    final who = names[rng.nextInt(names.length)];
    final roll = rng.nextInt(100);
    if (roll < 35) {
      actions.add(SeekBy(at, who, (rng.nextBool() ? -1 : 1) * between(5000, 120000)));
    } else if (roll < 50) {
      actions.add(Scrub(at, who, steps: between(3, 12), stepMs: (rng.nextBool() ? -1 : 1) * 10000, everyMs: between(250, 500)));
    } else if (roll < 75) {
      actions.add(TogglePlay(at, who));
    } else {
      actions.add(Stall(at, who, between(400, 8000)));
    }
    at += between(800, 12000);
  }
  // However the room ended up, someone presses play — it has to come back.
  actions.add(EnsurePlaying(at + 3000, 'host'));

  return Scenario('random', devices: devices, actions: actions, seed: seed, settleMs: 25000);
}
