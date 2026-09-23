import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/theme/tokens.dart';

void main() {
  test('smooth keeps the designed colours at the designed stops', () {
    const a = Color(0xFF000000), b = Color(0x80FF0000), c = Color(0x00FF0000);
    final (colors, stops) = AppGradients.smooth([a, b, c], [0, 0.4, 1]);
    expect(stops.first, 0);
    expect(stops.last, 1);
    expect(colors.first, a);
    expect(colors.last, c);
    final mid = stops.indexOf(0.4);
    expect(colors[mid].a, closeTo(b.a, 1e-9));
  });

  test('smooth is monotone and eases flat into both ends', () {
    const from = Color(0xFF000000), to = Color(0x00000000);
    final (colors, stops) = AppGradients.smooth([from, to], [0, 0.6]);
    final alphas = [for (final c in colors) c.a];
    for (var i = 1; i < alphas.length; i++) {
      expect(alphas[i], lessThanOrEqualTo(alphas[i - 1] + 1e-12));
    }
    // Flat at the ends: the first and last steps change far less than the
    // middle one.
    final first = alphas[0] - alphas[1];
    final middle = alphas[alphas.length ~/ 2 - 1] - alphas[alphas.length ~/ 2];
    final last = alphas[alphas.length - 2] - alphas.last;
    expect(first, lessThan(middle / 4));
    expect(last, lessThan(middle / 4));
    expect(stops.last, 0.6);
  });
}
