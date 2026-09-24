import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
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
      'a': [const MediaLibrary(id: '1', title: 'TV Shows', kind: MediaKind.show)],
      'b': [const MediaLibrary(id: '2', title: 'Shows', kind: MediaKind.show)],
    });
    expect(groups, hasLength(1));
    expect(groups.single.title, 'Shows');
    expect(groups.single.sectionsByServerId.keys, ['a', 'b']);
  });
}
