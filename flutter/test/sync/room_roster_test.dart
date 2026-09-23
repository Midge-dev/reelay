import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/sync/room_roster.dart';

void main() {
  group('waitingOnPhrase (screen 15)', () {
    final names = {'a': 'Marcus', 'b': 'Sam', 'c': 'Priya'};
    String? nameOf(String id) => names[id];

    test('names one person', () => expect(waitingOnPhrase(['a'], nameOf), 'Marcus'));
    test('names two people', () => expect(waitingOnPhrase(['a', 'b'], nameOf), 'Marcus and Sam'));
    test('counts three or more', () => expect(waitingOnPhrase(['a', 'b', 'c'], nameOf), '3 people'));
    test('never guesses a name it has not heard', () {
      expect(waitingOnPhrase(['zz'], nameOf), 'Someone');
      expect(waitingOnPhrase(['a', 'zz'], nameOf), '2 people');
    });
  });
}
