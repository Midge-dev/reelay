import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/clock_sync.dart';

void main() {
  test('onPong computes offset via the NTP-style formula and RTT', () {
    var fakeNow = 1000;
    final sync = ClockSync(sendPing: (_) {}, nowMsFn: () => fakeNow);

    // start() fires one ping synchronously (pingId == sentAt for the first
    // ping) before its periodic timer is even scheduled.
    sync.start();

    fakeNow = 1100; // 100ms round trip
    sync.onPong(1000, 1060); // remote timestamp roughly mid-flight
    sync.stop(); // safe now — onPong already consumed the pending entry

    // offset = remoteTimestamp - sentAt - rtt/2 = 1060 - 1000 - 50 = 10
    expect(sync.offsetMs, 10);
    expect(sync.minRttMs, 100);
  });

  test('a pong with negative or excessive RTT is discarded', () {
    var fakeNow = 1000;
    final sync = ClockSync(sendPing: (_) {}, nowMsFn: () => fakeNow);
    sync.start();

    fakeNow = 1000 + 6000; // 6s RTT, over the 5s cap
    sync.onPong(1000, 4000);
    sync.stop();

    expect(sync.offsetMs, isNull);
  });

  test('the lowest-RTT sample wins even if it is not the most recent one', () {
    var fakeNow = 1000;
    var lastPingId = 0;
    final sync = ClockSync(sendPing: (id) => lastPingId = id, nowMsFn: () => fakeNow);

    sync.start(); // first ping, id == 1000
    fakeNow = 1000 + 200;
    sync.onPong(lastPingId, 1000 + 200 ~/ 2 + 5); // 200ms RTT, offset 5
    sync.stop();

    fakeNow += 1;
    sync.start(); // second ping, fresh id
    final secondSentAt = lastPingId;
    fakeNow = secondSentAt + 50;
    sync.onPong(secondSentAt, secondSentAt + 50 ~/ 2 + 5); // 50ms RTT, offset 5
    sync.stop();

    expect(sync.minRttMs, 50);
  });
}
