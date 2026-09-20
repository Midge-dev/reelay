import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/playback_state.dart';

void main() {
  group('PlaybackState.targetPositionMs', () {
    test('while playing, extrapolates position forward from the anchor', () {
      final state = PlaybackState(
        seq: 1,
        phase: PlaybackPhase.playing,
        anchorPositionMs: 10000,
        anchorHostTimeMs: 100000,
      );

      expect(state.targetPositionMs(105000), 15000); // 5s elapsed since anchor
    });

    test('while playing, never returns a negative position', () {
      final state = PlaybackState(
        seq: 1,
        phase: PlaybackPhase.playing,
        anchorPositionMs: 0,
        anchorHostTimeMs: 100000,
      );

      expect(state.targetPositionMs(50000), 0); // hostNow before the anchor time
    });

    test('while paused, returns the anchor position unchanged regardless of host time', () {
      final state = PlaybackState(
        seq: 1,
        phase: PlaybackPhase.paused,
        anchorPositionMs: 42000,
        anchorHostTimeMs: 100000,
      );

      expect(state.targetPositionMs(999999), 42000);
    });
  });
}
