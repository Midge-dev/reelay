import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_response.dart';

void main() {
  test('PlexLibraryItem maps Genre/Collection JSON keys to genres/collections', () {
    final json = {
      'ratingKey': '123',
      'title': 'Arrival',
      'year': 2016,
      'Genre': [
        {'tag': 'Drama'},
        {'tag': 'Sci-Fi'},
      ],
      'Collection': [
        {'tag': 'Denis Villeneuve'},
      ],
    };

    final item = PlexLibraryItem.fromJson(json);

    expect(item.title, 'Arrival');
    expect(item.genres.map((g) => g.tag), ['Drama', 'Sci-Fi']);
    expect(item.collections.single.tag, 'Denis Villeneuve');
  });

  test('PlexPart maps Stream JSON key to streams, defaults missing list to empty', () {
    final withStreams = PlexPart.fromJson({
      'id': 1,
      'key': '/library/parts/1/file.mkv',
      'Stream': [
        {'streamType': 3, 'id': 9, 'language': 'English'},
      ],
    });
    expect(withStreams.streams.single.language, 'English');

    final withoutStreams = PlexPart.fromJson({'id': 1, 'key': '/library/parts/1/file.mkv'});
    expect(withoutStreams.streams, isEmpty);
  });

  test('extractMediaContainerList unwraps MediaContainer.Metadata for library items', () {
    final json = {
      'MediaContainer': {
        'Metadata': [
          {'ratingKey': '1', 'title': 'A'},
          {'ratingKey': '2', 'title': 'B'},
        ],
      },
    };

    final items = extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);

    expect(items.map((i) => i.ratingKey), ['1', '2']);
  });

  test('extractMediaContainerList returns empty list, not a throw, when the key is absent', () {
    final json = {'MediaContainer': <String, dynamic>{}};
    final items = extractMediaContainerList(json, 'Metadata', PlexLibraryItem.fromJson);
    expect(items, isEmpty);
  });

  test('PlexMovieDetail maps Media/Role/Director/Writer/Review JSON keys', () {
    final json = {
      'ratingKey': '10',
      'title': 'Dune',
      'Media': [
        {
          'Part': [
            {'id': 1, 'key': '/x'},
          ],
        },
      ],
      'Role': [
        {'tag': 'Timothee Chalamet'},
      ],
      'Director': [
        {'tag': 'Denis Villeneuve'},
      ],
      'Writer': [
        {'tag': 'Jon Spaihts'},
      ],
      'Review': [
        {'tag': 'Critic', 'text': 'Great film'},
      ],
    };

    final detail = PlexMovieDetail.fromJson(json);

    expect(detail.media.single.parts.single.key, '/x');
    expect(detail.roles.single.tag, 'Timothee Chalamet');
    expect(detail.directors.single.tag, 'Denis Villeneuve');
    expect(detail.writers.single.tag, 'Jon Spaihts');
    expect(detail.reviews.single.text, 'Great film');
  });
}
