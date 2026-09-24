import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/media/media_models.dart';
import 'package:reelay/data/plex/plex_mappers.dart';
import 'package:reelay/data/plex/plex_models.dart';

void main() {
  test('a library item keeps its ids, kind, tags and provider ids', () {
    final item = PlexLibraryItem.fromJson({
      'ratingKey': '7',
      'type': 'show',
      'title': 'Fringe',
      'guid': 'plex://show/abc',
      'Guid': [
        {'id': 'imdb://tt1119644'},
        {'id': 'tvdb://82066'},
      ],
      'Genre': [
        {'tag': 'Drama'},
      ],
      'Collection': [
        {'tag': 'Bad Robot'},
      ],
      'childCount': 5,
    }).toMedia();

    expect(item.id, '7');
    expect(item.kind, MediaKind.show);
    expect(item.guid, 'plex://show/abc');
    expect(item.externalIds, ['imdb://tt1119644', 'tvdb://82066']);
    expect(item.genres, ['Drama']);
    expect(item.collections, ['Bad Robot']);
    expect(item.childCount, 5);
  });

  test('an unknown type is other, not a movie', () {
    expect(plexKind('artist'), MediaKind.other);
    expect(plexKind(null), MediaKind.other);
  });

  test('a detail carries its provider ids, and its streams by kind', () {
    final detail = PlexMovieDetail.fromJson({
      'ratingKey': '100',
      'type': 'movie',
      'title': 'Arrival',
      'Guid': [
        {'id': 'tmdb://329865'},
      ],
      'Media': [
        {
          'Part': [
            {
              'id': 42,
              'key': '/library/parts/42/file.mkv',
              'Stream': [
                {'id': 1, 'streamType': 1, 'frameRate': 23.976},
                {'id': 2, 'streamType': 2, 'selected': true},
                {'id': 3, 'streamType': 3, 'key': '/library/streams/3'},
                {'id': 4, 'streamType': 4},
              ],
            },
          ],
        },
      ],
      'Role': [
        {'id': 9, 'tag': 'Amy Adams', 'role': 'Louise Banks', 'tagKey': 'global-9'},
      ],
    }).toMedia();

    expect(detail.kind, MediaKind.movie);
    expect(detail.externalIds, ['tmdb://329865']);
    final part = detail.media.single.parts.single;
    expect(part.id, '42');
    expect(part.streams.map((s) => s.kind), [StreamKind.video, StreamKind.audio, StreamKind.subtitle, StreamKind.other]);
    expect(part.streams[2].key, '/library/streams/3');
    final person = detail.roles.single;
    expect((person.id, person.name, person.role, person.globalId), ('9', 'Amy Adams', 'Louise Banks', 'global-9'));
  });
}
