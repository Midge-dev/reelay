import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart' show ServerReachability;
import 'package:reelay/state/duplicate_fold.dart';

const _attic = PlexServer(name: 'Attic', baseUrl: 'http://attic', accessToken: 'a', machineIdentifier: 'attic-id');
const _loft = PlexServer(name: 'Loft', baseUrl: 'http://loft', accessToken: 'l', machineIdentifier: 'loft-id');

String? _guidOf(String value) => value;

void main() {
  test('items with no guid never fold, each becomes its own singleton', () {
    final items = [
      Sourced<String>('a', _attic, ServerReachability.local),
      Sourced<String>('b', _loft, ServerReachability.local),
    ];
    final folded = foldByGuid<String>(items, guidOf: (_) => null);

    expect(folded, hasLength(2));
    expect(folded[0].guid, isNull);
    expect(folded[0].copies, hasLength(1));
    expect(folded[1].guid, isNull);
    expect(folded[1].copies, hasLength(1));
  });

  test('a shared guid across servers folds into one work with every copy', () {
    final items = [
      Sourced<String>('plex://movie/123', _attic, ServerReachability.local),
      Sourced<String>('plex://movie/123', _loft, ServerReachability.local),
    ];
    final folded = foldByGuid<String>(items, guidOf: _guidOf);

    expect(folded, hasLength(1));
    expect(folded.single.guid, 'plex://movie/123');
    expect(folded.single.copies, hasLength(2));
  });

  test('primary copy is the most reachable one, regardless of input order', () {
    final items = [
      Sourced<String>('plex://movie/123', _attic, ServerReachability.relayed),
      Sourced<String>('plex://movie/123', _loft, ServerReachability.local),
    ];
    final folded = foldByGuid<String>(items, guidOf: _guidOf);

    expect(folded.single.primary.server, _loft);
    expect(folded.single.primary.reachability, ServerReachability.local);
  });

  test('unreachable copies still fold in, ranked last', () {
    final items = [
      Sourced<String>('plex://movie/123', _attic, ServerReachability.unreachable),
      Sourced<String>('plex://movie/123', _loft, ServerReachability.relayed),
    ];
    final folded = foldByGuid<String>(items, guidOf: _guidOf);

    expect(folded.single.copies.map((c) => c.server), [_loft, _attic]);
  });

  test('different guids never merge, even from the same server', () {
    final items = [
      Sourced<String>('plex://movie/1', _attic, ServerReachability.local),
      Sourced<String>('plex://movie/2', _attic, ServerReachability.local),
    ];
    final folded = foldByGuid<String>(items, guidOf: _guidOf);

    expect(folded, hasLength(2));
  });

  test('empty input yields no folds', () {
    expect(foldByGuid<String>(const [], guidOf: _guidOf), isEmpty);
  });

  test('a lone item passes through as a singleton fold', () {
    final folded = foldByGuid<String>(
      [Sourced<String>('plex://movie/1', _attic, ServerReachability.local)],
      guidOf: _guidOf,
    );

    expect(folded, hasLength(1));
    expect(folded.single.copies, hasLength(1));
    expect(folded.single.primary.value, 'plex://movie/1');
  });

  test('preserves overall input order across folds', () {
    final items = [
      Sourced<String>('plex://movie/2', _attic, ServerReachability.local),
      Sourced<String>('plex://movie/1', _attic, ServerReachability.local),
      Sourced<String>('plex://movie/2', _loft, ServerReachability.local),
    ];
    final folded = foldByGuid<String>(items, guidOf: _guidOf);

    expect(folded.map((f) => f.guid), ['plex://movie/2', 'plex://movie/1']);
  });
}
