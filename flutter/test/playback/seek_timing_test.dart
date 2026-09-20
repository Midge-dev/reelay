import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/playback/seek_timing.dart';

void main() {
  test('accelerates the seek jump size with hold duration', () {
    expect(seekIncrementForHold(0), 10000);
    expect(seekIncrementForHold(1), 20000);
    expect(seekIncrementForHold(7), 20000);
    expect(seekIncrementForHold(8), 45000);
    expect(seekIncrementForHold(19), 45000);
    expect(seekIncrementForHold(20), 90000);
    expect(seekIncrementForHold(1000), 90000);
  });
}
