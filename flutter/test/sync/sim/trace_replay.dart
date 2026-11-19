import 'dart:convert';
import 'dart:math';

import 'sim_player.dart';
import 'sim_relay.dart';
import 'sim_room.dart';

/// Turns real Watch Together sessions — the `sync-traces/*.jsonl` files
/// devices write (see lib/sync/sync_trace.dart) — back into a [Scenario]:
/// who was in the room, how slow each player's seeks were, how far off
/// each clock was, and what each person pressed when. The engine's own
/// reactions aren't replayed; the simulation re-derives them, so a fix can
/// be checked against what actually happened.
///
/// One trace (just your Shield's, say) is enough: the other side is filled
/// in from what that device heard of it.
class DeviceTrace {
  DeviceTrace(this.name, this.entries);

  factory DeviceTrace.parse(String name, String jsonl) => DeviceTrace(name, [
    for (final line in const LineSplitter().convert(jsonl))
      if (line.trim().isNotEmpty) (jsonDecode(line) as Map<String, dynamic>).cast<String, Object?>(),
  ]);

  final String name;
  final List<Map<String, Object?>> entries;

  bool get isHost => entries.any((e) => e['type'] == 'session' && e['role'] == 'host');

  /// When the sync engine started (its first `session`) — the player
  /// screen presses play straight after.
  int get startT {
    for (final e in entries) {
      if (e['type'] == 'session') return e['t'] as int;
    }
    return entries.first['t'] as int;
  }

  /// hostNow = thisDeviceNow + offset (what ClockSync settled on); 0 on the host.
  int get clockOffsetMs {
    if (isHost) return 0;
    for (final e in entries.reversed) {
      if (e['type'] == 'sample' && e['clockOffset'] is int) return e['clockOffset'] as int;
    }
    return 0;
  }

  int? get minRttMs {
    int? best;
    for (final e in entries) {
      final rtt = e['rtt'];
      if (e['type'] == 'sample' && rtt is int && (best == null || rtt < best)) best = rtt;
    }
    return best;
  }

  /// Where the player was when the session began.
  int get startPositionMs {
    for (final e in entries) {
      if (e['pos'] is int && e['type'] != 'call') return e['pos'] as int;
    }
    return 0;
  }

  bool _isType(int i, String type, [String? key, Object? value]) {
    if (i < 0 || i >= entries.length) return false;
    final e = entries[i];
    return e['type'] == type && (key == null || e[key] == value);
  }

  /// How long each seek took to play again (seek → buffering → ready).
  List<int> get seekLatenciesMs {
    final out = <int>[];
    for (var i = 0; i < entries.length; i++) {
      if (!_isType(i, 'player', 'ev', 'seek')) continue;
      final t = entries[i]['t'] as int;
      int? bufferedAt;
      for (var j = i + 1; j < entries.length; j++) {
        final e = entries[j];
        if (e['type'] == 'player' && e['ev'] == 'seek') break;
        if (e['type'] != 'player' || e['ev'] != 'state') continue;
        if (e['value'] == 'buffering' && (e['t'] as int) - t <= 500) bufferedAt ??= e['t'] as int;
        if (e['value'] == 'ready' && bufferedAt != null) {
          out.add((e['t'] as int) - t);
          break;
        }
      }
      if (bufferedAt == null) out.add(0);
    }
    return out;
  }

  /// What the person did — everything the player reported that the sync
  /// engine didn't ask for — and buffering that no seek explains.
  List<({int t, SimAction Function(int atMs, String device) action})> get userActions {
    final out = <({int t, SimAction Function(int, String) action})>[];
    int? lastSeekT;
    var sawFirstPlay = false;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e['type'] != 'player') continue;
      final t = e['t'] as int;
      switch (e['ev']) {
        case 'seek':
          lastSeekT = t;
          final ownCall = _isType(i - 1, 'call', 'op', 'seekTo') && entries[i - 1]['value'] == e['value'];
          if (!ownCall) {
            final to = e['value'] as int;
            out.add((t: t, action: (at, d) => SeekTo(at, d, to)));
          }
        case 'playWhenReady':
          final playing = e['value'] == true;
          final ownCall = _isType(i - 1, 'call', 'op', playing ? 'play' : 'pause');
          // The player screen's own play() as the stream opens.
          if (playing && !sawFirstPlay && t - startT < 3000) {
            sawFirstPlay = true;
            continue;
          }
          if (!ownCall) out.add((t: t, action: (at, d) => playing ? EnsurePlaying(at, d) : EnsurePaused(at, d)));
        case 'state':
          if (e['value'] != 'buffering') continue;
          if (lastSeekT != null && t - lastSeekT <= 500) continue;
          final readyAt = entries
              .skip(i + 1)
              .firstWhere((x) => x['type'] == 'player' && x['ev'] == 'state' && x['value'] == 'ready', orElse: () => const {})['t'];
          final ms = readyAt is int ? readyAt - t : 5000;
          out.add((t: t, action: (at, d) => Stall(at, d, ms)));
      }
    }
    return out;
  }

  /// Other peers this device heard from, and how long each one's buffering
  /// spells lasted (from their statuses).
  Map<String, List<int>> get peerBufferingMs {
    final out = <String, List<int>>{};
    final since = <String, int>{};
    for (final e in entries) {
      if (e['type'] != 'in') continue;
      final ev = (e['event'] as Map).cast<String, Object?>();
      final from = ev['fromPeerId'];
      if (ev['kind'] != 'peerStatus' || from is! String) continue;
      out.putIfAbsent(from, () => []);
      if (ev['buffering'] == true) {
        since[from] ??= e['t'] as int;
      } else if (since[from] != null) {
        out[from]!.add((e['t'] as int) - since.remove(from)!);
      }
    }
    return out;
  }

  /// The first anchor the host sent this device.
  int? get firstAnchorMs {
    for (final e in entries) {
      if (e['type'] != 'in') continue;
      final ev = (e['event'] as Map).cast<String, Object?>();
      if (ev['kind'] == 'playbackState' && ev['anchorPositionMs'] is int) return ev['anchorPositionMs'] as int;
    }
    return null;
  }
}

PlayerProfile _profileFrom(List<int> latencies) {
  final real = latencies.where((l) => l > 0).toList();
  if (real.isEmpty) return PlayerProfile.directPlay;
  return PlayerProfile(seekLatencyMinMs: real.reduce(min), seekLatencyMaxMs: real.reduce(max));
}

/// A [Scenario] that puts the traced devices back in the room they were in.
Scenario scenarioFromTraces(String name, List<DeviceTrace> traces, {int settleMs = 25000}) {
  if (traces.isEmpty) throw ArgumentError('no traces');
  final hostTrace = traces.where((t) => t.isHost).firstOrNull;
  final guestTraces = traces.where((t) => !t.isHost).toList();

  // Everything on the host's clock, from when the first device arrived.
  int hostTime(DeviceTrace d, int t) => t + d.clockOffsetMs;
  final origin = traces.map((d) => hostTime(d, d.startT)).reduce(min);

  final rtts = [for (final g in guestTraces) ?g.minRttMs];
  final legMs = rtts.isEmpty ? 45 : max(10, rtts.reduce(min) ~/ 4);
  LinkProfile linkFor(DeviceTrace? d) {
    final rtt = d?.minRttMs;
    final leg = rtt == null ? legMs : max(10, rtt ~/ 4);
    return LinkProfile(upMs: leg, downMs: leg, jitterMs: 20);
  }

  final devices = <DeviceSpec>[];
  final actions = <SimAction>[];
  void addTraced(DeviceTrace d, String deviceName) {
    devices.add(DeviceSpec(
      deviceName,
      player: _profileFrom(d.seekLatenciesMs),
      link: linkFor(d.isHost ? null : d),
      startMs: d.startPositionMs,
      clockSkewMs: -d.clockOffsetMs,
      joinAtMs: hostTime(d, d.startT) - origin,
    ));
    for (final a in d.userActions) {
      actions.add(a.action(hostTime(d, a.t) - origin, deviceName));
    }
  }

  if (hostTrace != null) {
    addTraced(hostTrace, 'host');
  } else {
    // Only a guest's side: a host where that guest found it.
    final g = guestTraces.first;
    devices.add(DeviceSpec('host', link: LinkProfile(upMs: legMs, downMs: legMs, jitterMs: 20), startMs: g.firstAnchorMs ?? g.startPositionMs));
  }
  for (final g in guestTraces) {
    addTraced(g, g.name == 'host' ? 'guest' : g.name);
  }
  if (guestTraces.isEmpty) {
    // Only the host's side: the guests it heard from, as slow as their
    // buffering suggested.
    var n = 0;
    for (final entry in hostTrace!.peerBufferingMs.entries) {
      devices.add(DeviceSpec(
        'guest${++n}',
        player: _profileFrom(entry.value),
        link: LinkProfile(upMs: legMs, downMs: legMs, jitterMs: 20),
        startMs: hostTrace.startPositionMs,
      ));
    }
  }
  actions.sort((a, b) => a.atMs.compareTo(b.atMs));
  return Scenario(name, devices: devices, actions: actions, settleMs: settleMs);
}
