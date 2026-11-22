import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/focus/dpad_long_press.dart';

KeyDownEvent _down() => const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.select,
      logicalKey: LogicalKeyboardKey.select,
      timeStamp: Duration.zero,
    );

KeyUpEvent _up() => const KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.select,
      logicalKey: LogicalKeyboardKey.select,
      timeStamp: Duration.zero,
    );

void main() {
  test('a quick tap (below threshold) does not fire long-press, and the release is left unhandled', () {
    fakeAsync((async) {
      var fired = 0;
      final detector = DpadLongPressDetector(onLongPress: () => fired++);

      detector.handle(_down());
      async.elapse(const Duration(milliseconds: 100));
      final upResult = detector.handle(_up());

      expect(fired, 0);
      expect(upResult, KeyEventResult.ignored, reason: 'a short tap should still fall through to normal click handling');

      detector.dispose();
    });
  });

  test('holding past the threshold fires long-press once and swallows the release', () {
    fakeAsync((async) {
      var fired = 0;
      final detector = DpadLongPressDetector(onLongPress: () => fired++, threshold: const Duration(milliseconds: 500));

      detector.handle(_down());
      async.elapse(const Duration(milliseconds: 600));
      expect(fired, 1);

      final upResult = detector.handle(_up());
      expect(upResult, KeyEventResult.handled, reason: 'the trailing release must not also register as a click');

      detector.dispose();
    });
  });

  test('releasing and pressing again re-arms the detector', () {
    fakeAsync((async) {
      var fired = 0;
      final detector = DpadLongPressDetector(onLongPress: () => fired++, threshold: const Duration(milliseconds: 500));

      detector.handle(_down());
      async.elapse(const Duration(milliseconds: 600));
      detector.handle(_up());
      expect(fired, 1);

      detector.handle(_down());
      async.elapse(const Duration(milliseconds: 600));
      expect(fired, 2);

      detector.dispose();
    });
  });

  group('the hold, as the screen shows it (screen 21: "Hold, 600 ms")', () {
    test("fires at the design's 600 ms, not before", () {
      fakeAsync((async) {
        var fired = 0;
        final detector = DpadLongPressDetector(onLongPress: () => fired++);
        detector.handle(_down());
        async.elapse(const Duration(milliseconds: 550));
        expect(fired, 0);
        async.elapse(const Duration(milliseconds: 100));
        expect(fired, 1);
        detector.dispose();
      });
    });

    test('holding is true from the press until it fires or is let go', () {
      fakeAsync((async) {
        final detector = DpadLongPressDetector(onLongPress: () {});
        expect(detector.holding.value, isFalse);
        detector.handle(_down());
        expect(detector.holding.value, isTrue);
        async.elapse(const Duration(milliseconds: 200));
        detector.handle(_up()); // let go early
        expect(detector.holding.value, isFalse);

        detector.handle(_down());
        async.elapse(const Duration(milliseconds: 700)); // fires
        expect(detector.holding.value, isFalse, reason: 'done: the card is going, not still being held');
        detector.handle(_up());
        detector.dispose();
      });
    });
  });
}
