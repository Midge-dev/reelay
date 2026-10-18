import '../../data/media/media_models.dart';

enum SortMode {
  title('Title'),
  releaseDate('Release Date'),
  dateAdded('Date Added');

  final String label;
  const SortMode(this.label);
}

enum DateAddedBucket {
  last30Days('Last 30 days'),
  last6Months('Last 6 months'),
  thisYear('This year'),
  older('Older');

  final String label;
  const DateAddedBucket(this.label);
}

const _secondsPerDay = 86400;

int? _releaseYear(MediaItem item) {
  final fromDate =
      item.originallyAvailableAt != null &&
          item.originallyAvailableAt!.length >= 4
      ? int.tryParse(item.originallyAvailableAt!.substring(0, 4))
      : null;
  return fromDate ?? item.year;
}

int? decadeOf(MediaItem item) {
  final year = _releaseYear(item);
  if (year == null) return null;
  return (year ~/ 10) * 10;
}

bool matchesDateAddedBucket(
  MediaItem item,
  DateAddedBucket bucket,
  int nowEpochSeconds,
) {
  final addedAt = item.addedAt;
  if (addedAt == null) return false;
  final ageDays = (nowEpochSeconds - addedAt) ~/ _secondsPerDay;
  return switch (bucket) {
    DateAddedBucket.last30Days => ageDays <= 30,
    DateAddedBucket.last6Months => ageDays <= 182,
    DateAddedBucket.thisYear => ageDays <= 365,
    DateAddedBucket.older => ageDays > 365,
  };
}

/// A library's titles narrowed by query, genre, decade and date added, then sorted.
List<MediaItem> applyLibraryFilters({
  required List<MediaItem> items,
  required String query,
  required SortMode sortMode,
  String? genre,
  int? decade,
  DateAddedBucket? dateAddedBucket,
  String? collection,
  int? nowEpochSeconds,
}) {
  final now = nowEpochSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  var result = items.toList();

  if (query.trim().isNotEmpty) {
    final lowerQuery = query.toLowerCase();
    result = result
        .where((item) => item.title.toLowerCase().contains(lowerQuery))
        .toList();
  }
  if (genre != null) {
    result = result.where((item) => item.genres.contains(genre)).toList();
  }
  if (collection != null) {
    result = result
        .where((item) => item.collections.contains(collection))
        .toList();
  }
  if (decade != null) {
    result = result.where((item) => decadeOf(item) == decade).toList();
  }
  if (dateAddedBucket != null) {
    result = result
        .where((item) => matchesDateAddedBucket(item, dateAddedBucket, now))
        .toList();
  }

  switch (sortMode) {
    case SortMode.title:
      result.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case SortMode.releaseDate:
      result.sort(
        (a, b) => (_releaseYear(b) ?? -1 << 31).compareTo(
          _releaseYear(a) ?? -1 << 31,
        ),
      );
    case SortMode.dateAdded:
      result.sort((a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
  }

  return result;
}
