import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/state/app_state.dart';

void main() {
  group('normalizeLibraryTitle', () {
    test('drops Plex\'s stock "TV " prefix', () {
      expect(normalizeLibraryTitle('TV Shows'), 'Shows');
      expect(normalizeLibraryTitle('tv  series'), 'Series');
    });

    test('trims and collapses whitespace, otherwise keeps the owner\'s name', () {
      expect(normalizeLibraryTitle('  Standup   Specials '), 'Standup Specials');
      expect(normalizeLibraryTitle('Anime'), 'Anime');
      expect(normalizeLibraryTitle('TV Movies'), 'TV Movies');
    });
  });

  test('groupSections folds "TV Shows" and "Shows" on two servers into one entry', () {
    final groups = groupSections({
      'a': [const PlexSection(key: '1', title: 'TV Shows', type: 'show')],
      'b': [const PlexSection(key: '2', title: 'Shows', type: 'show')],
    });
    expect(groups, hasLength(1));
    expect(groups.single.title, 'Shows');
    expect(groups.single.sectionsByServerId.keys, ['a', 'b']);
  });

  test('home-video libraries (agent *.none) are not browsable', () {
    expect(const PlexSection(key: '1', title: 'Home Videos', type: 'movie', agent: 'com.plexapp.agents.none').isBrowsable, isFalse);
    expect(const PlexSection(key: '2', title: 'Other', type: 'movie', agent: 'tv.plex.agents.none').isBrowsable, isFalse);
    expect(const PlexSection(key: '3', title: 'Movies', type: 'movie', agent: 'tv.plex.agents.movie').isBrowsable, isTrue);
    expect(const PlexSection(key: '4', title: 'Music', type: 'artist').isBrowsable, isFalse);
  });
}
