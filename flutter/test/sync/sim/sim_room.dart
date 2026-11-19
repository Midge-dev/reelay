import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:reelay/sync/playback_state.dart';
import 'package:reelay/sync/sync_trace.dart';
import 'package:reelay/sync/sync_view_model.dart';
import 'package:reelay/sync/synced_player.dart';
import 'package:reelay/sync/time_utils.dart';

import 'sim_player.dart';
import 'sim_relay.dart';

/// One device in a simulated room. The first in a [Scenario] hosts.
class DeviceSpec {
  final String name;
  final PlayerProfile player;
  final LinkProfile link;

  /// Where this device's player opens (its own resume point).
  final int startMs;

  /// How far this device's wall clock is off the host's.
  final int clockSkewMs;

  /// When it arrives in the room, after the host.
  final int joinAtMs;

  const DeviceSpec(
    this.name, {
    this.player = PlayerProfile.directPlay,
    this.link = LinkProfile.home,
    this.startMs = 600000,
    this.clockSkewMs = 0,
    this.joinAtMs = 0,
  });

  @override
  String toString() =>
      '$name: player $player; link $link; opens at ${startMs}ms; clock ${clockSkewMs >= 0 ? '+' : ''}${clockSkewMs}ms'
      '${joinAtMs > 0 ? '; joins at ${joinAtMs}ms' : ''}';
}

/// Something a person (or their network) does, [atMs] into the run.
sealed class SimAction {
  final int atMs;
  final String device;
  const SimAction(this.atMs, this.device);
}

/// The player bar's rewind/forward: from the reported position, like
/// PlayerScreen._seekBy.
class SeekBy extends SimAction {
  final int deltaMs;
  const SeekBy(super.atMs, super.device, this.deltaMs);
  @override
  String toString() => '${atMs}ms $device seeks ${deltaMs >= 0 ? '+' : ''}${deltaMs}ms';
}

/// A seek to an exact spot — what a replayed trace knows.
class SeekTo extends SimAction {
  final int positionMs;
  const SeekTo(super.atMs, super.device, this.positionMs);
  @override
  String toString() => '${atMs}ms $device seeks to ${positionMs}ms';
}

/// Holding the D-pad on the progress bar: [steps] seeks of [stepMs], one
/// every [everyMs] — each from the reported position, which may not have
/// caught up with the last.
class Scrub extends SimAction {
  final int steps;
  final int stepMs;
  final int everyMs;
  const Scrub(super.atMs, super.device, {required this.steps, required this.stepMs, this.everyMs = 350});
  @override
  String toString() => '${atMs}ms $device scrubs $steps × ${stepMs}ms';
}

/// The play/pause button, like PlayerScreen._togglePlayPause.
class TogglePlay extends SimAction {
  const TogglePlay(super.atMs, super.device);
  @override
  String toString() => '${atMs}ms $device presses play/pause';
}

/// Make sure the room ends up playing: press play on [device] if it isn't.
class EnsurePlaying extends SimAction {
  const EnsurePlaying(super.atMs, super.device);
  @override
  String toString() => '${atMs}ms $device presses play if paused';
}

/// Press pause on [device] if it's playing.
class EnsurePaused extends SimAction {
  const EnsurePaused(super.atMs, super.device);
  @override
  String toString() => '${atMs}ms $device presses pause if playing';
}

/// The network or the server can't keep up: buffer for [ms].
class Stall extends SimAction {
  final int ms;
  const Stall(super.atMs, super.device, this.ms);
  @override
  String toString() => '${atMs}ms $device buffers for ${ms}ms';
}

/// A subtitle, quality or audio change: PlayerScreen throws the player
/// away and opens a new stream at the same spot, with a new
/// SyncViewModel on the same relay connection and trace.
class RestartStream extends SimAction {
  const RestartStream(super.atMs, super.device);
  @override
  String toString() => '${atMs}ms $device restarts its stream (subtitles/quality)';
}

/// The host moves the room on to the next episode: its player restarts at
/// 0 with a new sync session that knows the room's guests; each guest
/// follows [followAfterMs] later (finding its own copy, opening it), also
/// at 0.
class SwitchEpisode extends SimAction {
  final int followAfterMs;
  const SwitchEpisode(int atMs, {this.followAfterMs = 1500}) : super(atMs, 'host');
  @override
  String toString() => '${atMs}ms the host plays the next episode (guests follow ${followAfterMs}ms later)';
}

/// The device vanishes from the room without saying so.
class Drop extends SimAction {
  const Drop(super.atMs, super.device);
  @override
  String toString() => '${atMs}ms $device drops out';
}

class Scenario {
  final String name;
  final List<DeviceSpec> devices;
  final List<SimAction> actions;
  final int seed;

  /// How long after the last action the room has to be back in sync.
  final int settleMs;

  /// How long to keep watching once it should have settled.
  final int holdMs;

  const Scenario(
    this.name, {
    required this.devices,
    this.actions = const [],
    this.seed = 1,
    this.settleMs = 20000,
    this.holdMs = 15000,
  });

  int get lastActionMs {
    var last = devices.map((d) => d.joinAtMs).fold(0, max);
    for (final a in actions) {
      final end = a is Scrub ? a.atMs + a.steps * a.everyMs : a.atMs;
      last = max(last, end);
    }
    return last;
  }

  int get runForMs => lastActionMs + settleMs + holdMs;

  @override
  String toString() => [
    'scenario "$name" (seed $seed)',
    for (final d in devices) '  $d',
    for (final a in actions) '  $a',
  ].join('\n');
}

class _Device {
  _Device(this.spec, this.player, this.relay, this.trace, this.vm);
  final DeviceSpec spec;
  SimPlayer player;
  final SimRelayClient relay;
  final SyncTrace trace;
  SyncViewModel vm;
  PlaybackPhase? phase;
  bool present = true;
}

class RoomSample {
  final int t;
  final PlaybackPhase? hostPhase;
  final String hostName;
  final Map<String, ({int pos, bool playing, bool buffering})> devices;
  const RoomSample(this.t, this.hostPhase, this.hostName, this.devices);

  /// The furthest any guest is from the host. Guests each correct toward
  /// the host, not each other, so two guests can sit either side of it.
  int get offHostMs {
    final hostPos = devices[hostName]?.pos;
    if (hostPos == null) return 0;
    return devices.values.map((d) => (d.pos - hostPos).abs()).fold(0, max);
  }

  int get spreadMs {
    if (devices.length < 2) return 0;
    final positions = devices.values.map((d) => d.pos);
    return positions.reduce(max) - positions.reduce(min);
  }

  /// Everyone's on the same frame, give or take, and doing the same thing.
  bool get inSync {
    final phase = hostPhase;
    if (phase != PlaybackPhase.playing && phase != PlaybackPhase.paused) return false;
    final playing = phase == PlaybackPhase.playing;
    for (final d in devices.values) {
      if (d.playing != playing || d.buffering) return false;
    }
    return offHostMs <= RoomResult.inSyncMs;
  }
}

class RoomResult {
  /// The guests' deadband is 1500ms and `video_player` reports position up
  /// to 500ms late, so a guest inside 2s of the host is as in sync as it's
  /// built to be.
  static const inSyncMs = 2000;

  RoomResult(this.scenario, this.samples, this.traces, this.syncSeeks, this.t0);

  final Scenario scenario;
  final List<RoomSample> samples;
  final Map<String, SyncTrace> traces;

  /// Seeks the sync engine made on each device (not the person's own).
  final Map<String, int> syncSeeks;
  final int t0;

  int get totalSyncSeeks => syncSeeks.values.fold(0, (a, b) => a + b);

  /// From the last action until the room was in sync for good; null if it
  /// never got there.
  int? get timeToSyncMs {
    int? since;
    for (final s in samples) {
      if (s.t < scenario.lastActionMs) continue;
      if (s.inSync) {
        since ??= s.t;
      } else {
        since = null;
      }
    }
    return since == null ? null : since - scenario.lastActionMs;
  }

  bool get endsPlaying => samples.isNotEmpty && samples.last.hostPhase == PlaybackPhase.playing;

  /// What went wrong, in enough detail to see why: the scenario, the
  /// numbers, how the room looked once a second near the end, and the last
  /// stretch of every device's trace interleaved.
  String describe({int traceLines = 80}) {
    final b = StringBuffer()
      ..writeln(scenario)
      ..writeln('time to sync after last action: ${timeToSyncMs == null ? 'NEVER' : '${timeToSyncMs}ms'}')
      ..writeln('sync seeks: $syncSeeks')
      ..writeln('room, once a second over the last 20s:');
    final tail = samples.where((s) => s.t >= samples.last.t - 20000 && s.t % 1000 == 0);
    for (final s in tail) {
      final ds = s.devices.entries
          .map((e) => '${e.key}=${(e.value.pos / 1000).toStringAsFixed(1)}s${e.value.playing ? '▶' : '⏸'}${e.value.buffering ? '…' : ''}')
          .join(' ');
      b.writeln('  ${_secs(s.t)} host ${s.hostPhase?.name}  $ds  off host ${s.offHostMs}ms');
    }
    b.writeln('last $traceLines trace entries:');
    var i = 0;
    final skews = {for (final d in scenario.devices) d.name: d.clockSkewMs};
    final merged = [
      for (final e in traces.entries)
        for (final entry in e.value.entries)
          (device: e.key, entry: {...entry, 't': (entry['t'] as int) - (skews[e.key] ?? 0)}, i: i++),
    ]..sort((a, b) {
        final byTime = (a.entry['t'] as int).compareTo(b.entry['t'] as int);
        return byTime != 0 ? byTime : a.i.compareTo(b.i); // List.sort isn't stable
      });
    for (final m in merged.skip(max(0, merged.length - traceLines))) {
      b.writeln('  ${_secs((m.entry['t'] as int) - t0)} ${m.device.padRight(7)} ${traceEntrySummary(m.entry)}');
    }
    return b.toString();
  }

  static String _secs(int ms) => '+${(ms / 1000).toStringAsFixed(2)}s'.padLeft(9);
}

/// One trace entry as a short line, for failure output.
String traceEntrySummary(Map<String, Object?> e) {
  final type = e['type'];
  switch (type) {
    case 'in':
    case 'out':
      final ev = (e['event'] as Map).cast<String, Object?>();
      final kind = ev['kind'];
      final detail = switch (kind) {
        'playbackState' =>
          '${ev['phase']} anchor=${ev['anchorPositionMs']} seq=${ev['seq']}'
              '${ev['actionHint'] != null ? ' hint=${ev['actionHint']}' : ''}'
              '${(ev['waitingOn'] as List?)?.isNotEmpty == true ? ' waitingOn=${ev['waitingOn']}' : ''}',
        'peerStatus' => 'ready=${ev['ready']} buffering=${ev['buffering']} pos=${ev['positionMs']}',
        'controlRequest' => '${ev['requestKind']}${ev['positionMs'] != null ? ' ${ev['positionMs']}' : ''}',
        _ => '',
      };
      return '$type $kind $detail';
    case 'call':
      return 'call ${e['op']}${e['value'] != null ? ' ${e['value']}' : ''} (at ${e['pos']})';
    case 'player':
      return 'player ${e['ev']} ${e['value']}${e['pos'] != null ? ' (at ${e['pos']})' : ''}';
    case 'sample':
      return 'sample pos=${e['pos']} ${e['playing'] == true ? 'playing' : 'paused'} ${e['state']}';
    default:
      return '$type ${e.entries.where((x) => x.key != 't' && x.key != 'type').map((x) => '${x.key}=${x.value}').join(' ')}';
  }
}

/// Runs [scenario] in fake time: a [SimRelayServer], and per device a
/// [SimPlayer] driven by the app's own [SyncViewModel] — so it's the real
/// host/guest engines, wire format and clock sync under test.
RoomResult runRoom(Scenario scenario) {
  late RoomResult result;
  fakeAsync((async) {
    final random = Random(scenario.seed);
    final t0 = nowMs();
    final server = SimRelayServer(random: random, now: nowMs);
    final devices = <String, _Device>{};
    final samples = <RoomSample>[];
    final subscriptions = <StreamSubscription<Object?>>[];

    void join(DeviceSpec spec) {
      final player = SimPlayer(spec.player, random: random, startMs: spec.startMs);
      final relay = server.connect(spec.name, spec.link);
      int deviceNow() => nowMs() + spec.clockSkewMs;
      // Stamped with the device's own clock, like a real device's trace.
      final trace = SyncTrace(now: deviceNow);
      final vm = SyncViewModel(player: player, relay: relay, trace: trace, deviceClock: deviceNow);
      final device = _Device(spec, player, relay, trace, vm);
      devices[spec.name] = device;
      subscriptions.add(vm.phase.listen((p) => device.phase = p));
      vm.start();
      player.play(); // PlayerScreen plays once sync has started
    }

    for (final spec in scenario.devices) {
      if (spec.joinAtMs <= 0) {
        join(spec);
      } else {
        Timer(Duration(milliseconds: spec.joinAtMs), () => join(spec));
      }
    }

    void restart(_Device d, {required int at, List<String> peers = const []}) {
      d.vm.stop();
      d.player.dispose();
      final fresh = SimPlayer(d.spec.player, random: random, startMs: at);
      int deviceNow() => nowMs() + d.spec.clockSkewMs;
      d.player = fresh;
      d.vm = SyncViewModel(player: fresh, relay: d.relay, trace: d.trace, deviceClock: deviceNow, initialPeers: peers);
      subscriptions.add(d.vm.phase.listen((ph) => d.phase = ph));
      d.vm.start();
      fresh.play();
    }

    void act(SimAction action) {
      final d = devices[action.device];
      if (d == null || !d.present) return;
      final p = d.player;
      switch (action) {
        case SeekBy(:final deltaMs):
          p.seekTo((p.currentPosition + deltaMs).clamp(0, p.duration));
        case Scrub(:final steps, :final stepMs, :final everyMs):
          for (var i = 0; i < steps; i++) {
            Timer(Duration(milliseconds: i * everyMs), () {
              if (d.present) p.seekTo((p.currentPosition + stepMs).clamp(0, p.duration));
            });
          }
        case TogglePlay():
          p.isPlaying ? p.pause() : p.play();
        case EnsurePlaying():
          if (!p.isPlaying) p.play();
        case EnsurePaused():
          if (p.isPlaying) p.pause();
        case SeekTo(:final positionMs):
          p.seekTo(positionMs.clamp(0, p.duration));
        case Stall(:final ms):
          p.stall(ms);
        case RestartStream():
          restart(d, at: p.truePosition);
        case SwitchEpisode(:final followAfterMs):
          restart(d, at: 0, peers: d.vm.knownPeers);
          for (final g in devices.values) {
            if (identical(g, d) || !g.present) continue;
            // As PlayerScreen does: the moment the switch arrives, the old
            // stream's sync stops (so it can't tell the host's new session
            // it's ready) and the player pauses; then it finds and opens
            // the episode.
            Timer(Duration(milliseconds: g.spec.link.downMs + d.spec.link.upMs), () {
              if (!g.present) return;
              g.vm.stop();
              g.player.pause();
            });
            Timer(Duration(milliseconds: followAfterMs), () {
              if (g.present) restart(g, at: 0);
            });
          }
        case Drop():
          d.present = false;
          d.relay.drop();
          d.vm.stop();
          d.player.dispose();
      }
    }

    for (final action in scenario.actions) {
      Timer(Duration(milliseconds: action.atMs), () => act(action));
    }

    Timer.periodic(const Duration(milliseconds: 250), (_) {
      final host = devices[scenario.devices.first.name];
      samples.add(RoomSample(nowMs() - t0, host?.phase, scenario.devices.first.name, {
        for (final d in devices.values)
          if (d.present)
            d.spec.name: (
              pos: d.player.truePosition,
              playing: d.player.isPlaying,
              buffering: d.player.playbackState == SyncPlaybackState.buffering,
            ),
      }));
    });

    async.elapse(Duration(milliseconds: scenario.runForMs));

    for (final d in devices.values) {
      if (d.present) {
        d.vm.stop();
        d.player.dispose();
      }
    }
    for (final s in subscriptions) {
      s.cancel();
    }
    async.flushMicrotasks();

    result = RoomResult(
      scenario,
      samples,
      {for (final d in devices.values) d.spec.name: d.trace},
      {
        for (final d in devices.values)
          d.spec.name: d.trace.entries.where((e) => e['type'] == 'call' && e['op'] == 'seekTo').length,
      },
      t0,
    );
  });
  return result;
}
