import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/state/recency_merge.dart';

/// A title and when it was last played (epoch seconds), or null.
typedef _T = (String, int?);

List<String> _merge(List<List<_T>> lists) => [for (final t in mergeByRecency(lists, (t) => t.$2)) t.$1];

void main() {
  test('a title just played on one server goes ahead of older ones on another', () {
    final plex = <_T>[('Quiet Place', 300), ('Insidious', 200), ('300', 100)];
    final jellyfin = <_T>[('Tears of Steel', 400)];
    expect(_merge([plex, jellyfin]), ['Tears of Steel', 'Quiet Place', 'Insidious', '300']);
  });

  test('the lists interleave by time', () {
    final plex = <_T>[('a', 500), ('c', 300), ('e', 100)];
    final jellyfin = <_T>[('b', 400), ('d', 200)];
    expect(_merge([plex, jellyfin]), ['a', 'b', 'c', 'd', 'e']);
  });

  test('a next episode with no time keeps its place in its own server\'s list', () {
    final plex = <_T>[('a', 500), ('next ep', null), ('c', 100)];
    final jellyfin = <_T>[('b', 300)];
    expect(_merge([plex, jellyfin]), ['a', 'next ep', 'b', 'c'], reason: 'it rides with a, the title above it');
  });

  test('untimed titles at the top of a list take the time below them', () {
    final jellyfin = <_T>[('next ep', null), ('b', 300)];
    final plex = <_T>[('a', 400), ('c', 200)];
    expect(_merge([plex, jellyfin]), ['a', 'next ep', 'b', 'c']);
  });

  test('a list with no times goes after the timed ones, in its own order', () {
    final plex = <_T>[('a', 100)];
    final untimed = <_T>[('x', null), ('y', null)];
    expect(_merge([untimed, plex]), ['a', 'x', 'y']);
  });

  test('ties keep server order; one list or none comes back as it was', () {
    expect(
      _merge([
        <_T>[('a', 100)],
        <_T>[('b', 100)],
      ]),
      ['a', 'b'],
    );
    expect(
      _merge([
        <_T>[('a', 100), ('b', 300)],
      ]),
      ['a', 'b'],
      reason: 'never re-sorted within a server',
    );
    expect(_merge([]), isEmpty);
  });
}
