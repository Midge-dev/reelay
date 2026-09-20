import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/time_format.dart';

void main() {
  test('under an hour formats as m:ss', () {
    expect(formatTimecode(65000), '1:05');
  });

  test('an hour or more formats as h:mm:ss', () {
    expect(formatTimecode(3665000), '1:01:05');
  });

  test('zero formats as 0:00', () {
    expect(formatTimecode(0), '0:00');
  });
}
