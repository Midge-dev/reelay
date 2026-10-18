import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/screens/library/library_filters.dart';

const _oneYearSeconds = 365 * 86400;

void main() {
  group('decadeOf', () {
    test('prefers originallyAvailableAt over year', () {
      const item = MediaItem(id: '1', title: 'X', originallyAvailableAt: '1994-09-23', year: 2000);
      expect(decadeOf(item), 1990);
    });

    test('falls back to year when originallyAvailableAt is absent', () {
      const item = MediaItem(id: '1', title: 'X', year: 2016);
      expect(decadeOf(item), 2010);
    });

    test('returns null when neither is available', () {
      const item = MediaItem(id: '1', title: 'X');
      expect(decadeOf(item), isNull);
    });
  });

  group('matchesDateAddedBucket', () {
    test('an item with no addedAt never matches any bucket', () {
      const item = MediaItem(id: '1', title: 'X');
      expect(matchesDateAddedBucket(item, DateAddedBucket.older, 1000000), isFalse);
    });

    test('boundary: exactly 30 days old counts as last30Days, not older', () {
      final now = 1000000;
      final item = MediaItem(id: '1', title: 'X', addedAt: now - 30 * 86400);
      expect(matchesDateAddedBucket(item, DateAddedBucket.last30Days, now), isTrue);
    });

    test('an item older than a year matches only older', () {
      final now = 1000000;
      final item = MediaItem(id: '1', title: 'X', addedAt: now - _oneYearSeconds - 86400);
      expect(matchesDateAddedBucket(item, DateAddedBucket.thisYear, now), isFalse);
      expect(matchesDateAddedBucket(item, DateAddedBucket.older, now), isTrue);
    });
  });

  group('applyLibraryFilters', () {
    const items = [
      MediaItem(id: '1', title: 'Alien', year: 1979, genres: ['Horror'], addedAt: 300),
      MediaItem(id: '2', title: 'Arrival', year: 2016, genres: ['Sci-Fi'], addedAt: 100),
      MediaItem(id: '3', title: 'zodiac', year: 2007, genres: ['Thriller'], addedAt: 200),
    ];

    test('query filters case-insensitively by title substring', () {
      final result = applyLibraryFilters(items: items, query: 'ar', sortMode: SortMode.title);
      expect(result.map((i) => i.id), ['2']);
    });

    test('genre filters by exact tag match', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title, genre: 'Horror');
      expect(result.map((i) => i.id), ['1']);
    });

    test('sortMode.title sorts case-insensitively', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title);
      expect(result.map((i) => i.title), ['Alien', 'Arrival', 'zodiac']);
    });

    test('sortMode.releaseDate sorts newest first', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.releaseDate);
      expect(result.map((i) => i.id), ['2', '3', '1']);
    });

    test('sortMode.dateAdded sorts most-recently-added first', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.dateAdded);
      expect(result.map((i) => i.id), ['1', '3', '2']);
    });

    test('decade filters using decadeOf', () {
      final result = applyLibraryFilters(items: items, query: '', sortMode: SortMode.title, decade: 2010);
      expect(result.map((i) => i.id), ['2']);
    });

    test('collection filters by exact tag match', () {
      const withCollection = MediaItem(id: '4', title: 'Alien 2', collections: ['Alien Franchise']);
      final result = applyLibraryFilters(items: [...items, withCollection], query: '', sortMode: SortMode.title, collection: 'Alien Franchise');
      expect(result.map((i) => i.id), ['4']);
    });
  });
}
