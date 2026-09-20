import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/relay_status.dart';
import 'package:reelay/sync/relay_protocol.dart';

void main() {
  test('connecting for the first time goes silent -> waking -> failed on the fixed timeline', () {
    fakeAsync((async) {
      final controller = StreamController<ConnectionState>();
      final tracker = RelayStatusTracker(controller.stream, initial: ConnectionState.connecting);
      async.flushMicrotasks();

      expect(tracker.status.value, RelayStatus.silent);

      async.elapse(const Duration(milliseconds: 2000));
      expect(tracker.status.value, RelayStatus.waking);

      async.elapse(const Duration(milliseconds: 73000));
      expect(tracker.status.value, RelayStatus.failed);

      tracker.dispose();
      controller.close();
    });
  });

  test('connecting successfully shows connectedConfirm then settles to dotOnly', () {
    fakeAsync((async) {
      final controller = StreamController<ConnectionState>();
      final tracker = RelayStatusTracker(controller.stream, initial: ConnectionState.connecting);
      async.flushMicrotasks();

      controller.add(ConnectionState.connected);
      async.flushMicrotasks();
      expect(tracker.status.value, RelayStatus.connectedConfirm);

      async.elapse(const Duration(milliseconds: 2000));
      expect(tracker.status.value, RelayStatus.dotOnly);

      tracker.dispose();
      controller.close();
    });
  });

  test('a drop after having connected once shows reconnecting immediately, no waking delay', () {
    fakeAsync((async) {
      final controller = StreamController<ConnectionState>();
      final tracker = RelayStatusTracker(controller.stream, initial: ConnectionState.connected);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2000)); // settle to dotOnly

      controller.add(ConnectionState.reconnecting);
      async.flushMicrotasks();

      expect(tracker.status.value, RelayStatus.reconnecting);

      // No waking/failed timeline should fire for an already-seen relay.
      async.elapse(const Duration(seconds: 80));
      expect(tracker.status.value, RelayStatus.reconnecting);

      tracker.dispose();
      controller.close();
    });
  });

  test('room full or not found reports failed immediately', () {
    fakeAsync((async) {
      final controller = StreamController<ConnectionState>();
      final tracker = RelayStatusTracker(controller.stream, initial: ConnectionState.disconnected);
      async.flushMicrotasks();

      controller.add(ConnectionState.roomFull);
      async.flushMicrotasks();

      expect(tracker.status.value, RelayStatus.failed);

      tracker.dispose();
      controller.close();
    });
  });

  test('a disconnected/idle state never starts the waking/failed timeline', () {
    fakeAsync((async) {
      final controller = StreamController<ConnectionState>();
      final tracker = RelayStatusTracker(controller.stream, initial: ConnectionState.disconnected);
      async.flushMicrotasks();

      expect(tracker.status.value, RelayStatus.silent);
      async.elapse(const Duration(seconds: 80));
      expect(tracker.status.value, RelayStatus.silent);

      tracker.dispose();
      controller.close();
    });
  });
}
