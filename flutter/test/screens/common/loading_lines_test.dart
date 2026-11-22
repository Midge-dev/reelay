import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/screens/common/loading_lines.dart';

void main() {
  test('every loading line is its own, in the house style', () {
    expect(loadingLines.toSet(), hasLength(loadingLines.length), reason: 'no repeats');
    for (final line in loadingLines) {
      expect(line.endsWith('…'), isTrue, reason: '"$line" ends in an ellipsis character');
      expect(line[0], line[0].toUpperCase(), reason: '"$line": sentence case');
      expect(line.length, lessThanOrEqualTo(34), reason: '"$line" fits on one line under the wait');
    }
  });

  test('a pick is one of them', () {
    expect(loadingLines, contains(pickLoadingLine(Random(1))));
  });
}
