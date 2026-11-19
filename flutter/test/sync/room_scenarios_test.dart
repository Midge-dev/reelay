import 'package:flutter_test/flutter_test.dart';

import 'sim/sim_player.dart';
import 'sim/sim_relay.dart';
import 'sim/sim_room.dart';

/// Whole-room behaviour: a host and guests running the real sync engine
/// against simulated players and a simulated relay (see test/sync/sim/).
/// Each scenario is something that happens in a real room; each must end
/// with everyone on the same frame, doing the same thing, without the sync
/// engine thrashing.
void main() {
  const host = DeviceSpec('host', player: PlayerProfile.directPlay);
  const remoteGuest = DeviceSpec('guest', player: PlayerProfile.remoteTranscode, link: LinkProfile.far);

  void expectSettles(RoomResult r, {int withinMs = 20000, int? maxSyncSeeks, bool playing = true}) {
    final why = r.describe();
    expect(r.timeToSyncMs, isNotNull, reason: 'never settled\n$why');
    expect(r.timeToSyncMs, lessThanOrEqualTo(withinMs), reason: 'settled too slowly\n$why');
    expect(r.endsPlaying, playing, reason: 'ended ${playing ? 'paused' : 'playing'}\n$why');
    if (maxSyncSeeks != null) {
      expect(r.totalSyncSeeks, lessThanOrEqualTo(maxSyncSeeks), reason: 'too many corrective seeks\n$why');
    }
  }

  group('starting a room', () {
    test('everyone opens at the same spot', () {
      expectSettles(runRoom(const Scenario('same spot', devices: [host, remoteGuest])), maxSyncSeeks: 1);
    });

    test('each side opens at its own resume point (the "start where we left off" room)', () {
      final r = runRoom(const Scenario('own resume points', devices: [
        DeviceSpec('host', startMs: 2400000),
        DeviceSpec('guest', player: PlayerProfile.remoteTranscode, link: LinkProfile.far, startMs: 2391000),
      ]));
      expectSettles(r, maxSyncSeeks: 3);
    });

    test('a guest arrives once the host is already watching', () {
      final r = runRoom(const Scenario('late join', devices: [
        host,
        DeviceSpec('guest', player: PlayerProfile.remoteTranscode, link: LinkProfile.far, joinAtMs: 20000),
      ]));
      expectSettles(r, maxSyncSeeks: 3);
    });

    test("a guest whose clock is minutes off still lands on the host's frame", () {
      final r = runRoom(const Scenario('skewed clock', devices: [
        host,
        DeviceSpec('guest', player: PlayerProfile.remoteTranscode, link: LinkProfile.far, clockSkewMs: -4 * 60000),
      ]));
      expectSettles(r, maxSyncSeeks: 3);
    });
  });

  group('seeking', () {
    test('the host rewinds 30s', () {
      final r = runRoom(const Scenario('host rewind', devices: [host, remoteGuest], actions: [SeekBy(15000, 'host', -30000)]));
      expectSettles(r, maxSyncSeeks: 4);
    });

    test('the guest rewinds 30s', () {
      final r = runRoom(const Scenario('guest rewind', devices: [host, remoteGuest], actions: [SeekBy(15000, 'guest', -30000)]));
      expectSettles(r, maxSyncSeeks: 5);
    });

    test('the host holds the D-pad to scrub back two minutes', () {
      final r = runRoom(const Scenario('host scrub', devices: [host, remoteGuest], actions: [
        Scrub(15000, 'host', steps: 12, stepMs: -10000),
      ]));
      expectSettles(r, maxSyncSeeks: 8);
    });

    test('the guest scrubs forward while the host is mid-seek', () {
      final r = runRoom(const Scenario('crossed seeks', devices: [host, remoteGuest], actions: [
        SeekBy(15000, 'host', -60000),
        Scrub(15500, 'guest', steps: 6, stepMs: 10000),
      ]));
      expectSettles(r, maxSyncSeeks: 10);
    });

    test('rewinding again and again, like looking for a line you missed', () {
      final r = runRoom(Scenario('repeated rewinds', devices: const [host, remoteGuest], actions: [
        for (var i = 0; i < 5; i++) SeekBy(15000 + i * 6000, i.isEven ? 'host' : 'guest', -10000),
      ]));
      expectSettles(r, maxSyncSeeks: 15);
    });
  });

  group('pausing', () {
    test('the guest pauses and the host resumes', () {
      final r = runRoom(const Scenario('pause/resume', devices: [host, remoteGuest], actions: [
        TogglePlay(15000, 'guest'),
        TogglePlay(25000, 'host'),
      ]));
      expectSettles(r, maxSyncSeeks: 3);
    });

    test('pausing just after a rewind, then resuming', () {
      final r = runRoom(const Scenario('pause after rewind', devices: [host, remoteGuest], actions: [
        SeekBy(15000, 'host', -30000),
        TogglePlay(23000, 'host'),
        TogglePlay(30000, 'host'),
      ]));
      expectSettles(r, maxSyncSeeks: 5);
    });

    test('a pause the room ends in stays paused, everyone on the same frame', () {
      final r = runRoom(const Scenario('ends paused', devices: [host, remoteGuest], actions: [
        SeekBy(15000, 'guest', -20000),
        TogglePlay(45000, 'host'), // once the rewind has settled
      ]));
      expectSettles(r, playing: false, maxSyncSeeks: 5);
    });
  });

  group('bad networks', () {
    test('the guest buffers for 5s mid-show', () {
      final r = runRoom(const Scenario('guest stall', devices: [host, remoteGuest], actions: [Stall(20000, 'guest', 5000)]));
      expectSettles(r, maxSyncSeeks: 3);
    });

    test('the host buffers for 5s mid-show', () {
      final r = runRoom(const Scenario('host stall', devices: [host, remoteGuest], actions: [Stall(20000, 'host', 5000)]));
      expectSettles(r, maxSyncSeeks: 3);
    });

    test('short hiccups on both sides', () {
      final r = runRoom(Scenario('hiccups', devices: const [host, remoteGuest], actions: [
        for (var i = 0; i < 6; i++) Stall(15000 + i * 4000, i.isEven ? 'guest' : 'host', 600 + i * 150),
      ]));
      expectSettles(r, maxSyncSeeks: 8);
    });
  });

  group('bigger rooms', () {
    test('three guests with very different players and links', () {
      final r = runRoom(const Scenario('four devices', devices: [
        host,
        DeviceSpec('lan', player: PlayerProfile.directPlay, link: LinkProfile.lan),
        DeviceSpec('remote', player: PlayerProfile.remoteTranscode, link: LinkProfile.far, startMs: 595000),
        DeviceSpec('slow', player: PlayerProfile(seekLatencyMinMs: 4000, seekLatencyMaxMs: 6000), link: LinkProfile.home),
      ], actions: [
        SeekBy(20000, 'lan', -45000),
        TogglePlay(35000, 'remote'),
        TogglePlay(40000, 'remote'),
      ]));
      expectSettles(r, maxSyncSeeks: 14);
    });

    test('a guest dropping out while it buffers does not hold up the rest for long', () {
      final r = runRoom(const Scenario('drop while buffering', devices: [
        host,
        DeviceSpec('stays', player: PlayerProfile.directPlay),
        DeviceSpec('leaves', player: PlayerProfile.remoteTranscode, link: LinkProfile.far),
      ], actions: [
        Stall(20000, 'leaves', 30000),
        Drop(23500, 'leaves'),
      ]));
      expectSettles(r, withinMs: 5000);
    });
  });
}
