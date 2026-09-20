import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/library_filters.dart';

const _oneYearSeconds = 365 * 86400;

void main() {
  group('decadeOf', () {
    test('prefers originallyAvailableAt over year', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'X', originallyAvailableAt: '1994-09-23', year: 2000);
      expect(decadeOf(item), 1990);
    });

    test('falls back to year when originallyAvailableAt is absent', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'X', year: 2016);
      expect(decadeOf(item), 2010);
    });

    test('returns null when neither is available', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'X');
      expect(decadeOf(item), isNull);
    });
  });

  group('matchesDateAddedBucket', () {
    test('an item with no addedAt never matches any bucket', () {
      const item = PlexLibraryItem(ratingKey: '1', title: 'X');
      expect(matchesDateAddedBucket(item, DateAddedBucket.older, 1000000), isFalse);
    });

    test('boundary: exactly 30 days old counts as last30Days, not older', () {
      final now = 1000000;
      final item = PlexLibraryItem(ratingKey: '1', title: 'X', addedAt: now - 30 * 86400);
      expect(matchesDateAddedBucket(item, DateAddedBucket.last30Days, now), isTrue);
    });

    test('an item older than a year matches only older', () {
      final now = 1000000;
      final item = PlexLibraryItem(ratingKey: '1', title: 'X', addedAt: now - _oneYearSeconds - 86400);
      expect(matchesDateAddedBucket(item, DateAddedBucket.thisYear, now), isFalse);
      expect(matchesDateAddedBucket(item, DateAddedBucket.older, now), isTrue);
    });
  });

  group('applyLibraryFilters', () {
    const items = [
      PlexLibraryItem(ratingKey: '1', title: 'Alien', year: 1979, genres: [PlexTag(tag: 'Horror')], addedAt: 300),
      PlexLibraryItem(ratingKey: '2', title: 'Arrival', year: 2016, genres: [PlexTag(tag: 'Sci-Fi')], addedAt: 100),
      PlexLibraryItem(ratingKey: '3', title: 'zodiac', year: 2007, genres: [PlexTag(tag: 'Thriller')], addedAt: 200),
    ];

    test('query filters case-insensitively by title substring', () {
      final result = applyLibraryFilters(items: items, query: 'ar', sortMode: SortMode.title);
      expect(result.map((i) => i.ratingKey), ['2']);
    });

    test('genre filters by exact tag match', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title, genre: 'Horror');
      expect(result.map((i) => i.ratingKey), ['1']);
    });

    test('sortMode.title sorts case-insensitively', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title);
      expect(result.map((i) => i.title), ['Alien', 'Arrival', 'zodiac']);
    });

    test('sortMode.releaseDate sorts newest first', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.releaseDate);
      expect(result.map((i) => i.ratingKey), ['2', '3', '1']);
    });

    test('sortMode.dateAdded sorts most-recently-added first', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.dateAdded);
      expect(result.map((i) => i.ratingKey), ['1', '3', '2']);
    });

    test('decade filters using decadeOf', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title, decade: 2010);
      expect(result.map((i) => i.ratingKey), ['2']);
    });

    test('collection filters by exact tag match', () {
      const withCollection = PlexLibraryItem(ratingKey: '4', title: 'Alien 2', collections: [PlexTag(tag: 'Alien Franchise')]);
      final result = applyLibraryFilters(items: [...items, withCollection], query: '', sortMode: SortMode.title, collection: 'Alien Franchise');
      expect(result.map((i) => i.ratingKey), ['4']);
    });
  });
}
