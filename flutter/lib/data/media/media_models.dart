/// Backend-neutral content models. A client maps its own wire format into
/// these (data/plex/plex_mappers.dart for Plex); screens, state and
/// playback never see a backend's own types.
library;

enum MediaKind { movie, show, season, episode, collection, other }

/// A library on one server — what the rail's [SectionGroup]s are made of.
class MediaLibrary {
  final String id;
  final String title;
  final MediaKind kind;

  const MediaLibrary({required this.id, required this.title, required this.kind});
}

/// Any browsable thing: a movie, show, season, episode or collection, as a
/// list/row/grid response carries it. The full picture of one title (files,
/// people, reviews) is a [MediaDetail].
///
/// Times are milliseconds; [addedAt] and [lastViewedAt] are epoch seconds.
class MediaItem {
  final String id;
  final MediaKind kind;
  final String title;

  /// A season's show; an episode's season title.
  final String? parentTitle;

  /// A season's show id.
  final String? parentId;

  /// An episode's show title.
  final String? grandparentTitle;

  /// An episode's season number.
  final int? parentIndex;

  /// A season's or episode's own number.
  final int? index;

  final int? year;
  final String? thumb;
  final String? art;
  final String? summary;
  final int? addedAt;

  /// Release date, `yyyy-mm-dd`.
  final String? originallyAvailableAt;
  final String? contentRating;

  /// The server's own primary id for the work (Plex's agent guid). Two
  /// copies fold on this or on any of [externalIds] — see duplicate_fold.
  final String? guid;

  /// Provider ids normalised to `imdb://tt…`, `tmdb://…`, `tvdb://…`, the
  /// same on every backend, which is what lets a Plex and a Jellyfin copy of
  /// one film fold together.
  final List<String> externalIds;

  /// Total episode count on a show.
  final int? leafCount;

  /// Season count on a show; item count on a collection.
  final int? childCount;

  final List<String> genres;
  final List<String> collections;

  final int? duration;
  final int? viewOffset;

  /// When it was last played, epoch seconds — how Continue Watching
  /// orders one server's titles against another's. Null when the server
  /// doesn't say (a show's next episode, which hasn't been played).
  final int? lastViewedAt;

  /// Times fully watched; 0/null means unwatched — how the show page finds
  /// "the next unwatched episode" to land on (screen 04).
  final int? viewCount;

  const MediaItem({
    required this.id,
    this.kind = MediaKind.other,
    required this.title,
    this.parentTitle,
    this.parentId,
    this.grandparentTitle,
    this.parentIndex,
    this.index,
    this.year,
    this.thumb,
    this.art,
    this.summary,
    this.addedAt,
    this.originallyAvailableAt,
    this.contentRating,
    this.guid,
    this.externalIds = const [],
    this.leafCount,
    this.childCount,
    this.genres = const [],
    this.collections = const [],
    this.duration,
    this.viewOffset,
    this.lastViewedAt,
    this.viewCount,
  });

  MediaItem copyWith({MediaKind? kind, String? title}) => MediaItem(
    id: id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    parentTitle: parentTitle,
    parentId: parentId,
    grandparentTitle: grandparentTitle,
    parentIndex: parentIndex,
    index: index,
    year: year,
    thumb: thumb,
    art: art,
    summary: summary,
    addedAt: addedAt,
    originallyAvailableAt: originallyAvailableAt,
    contentRating: contentRating,
    guid: guid,
    externalIds: externalIds,
    leafCount: leafCount,
    childCount: childCount,
    genres: genres,
    collections: collections,
    duration: duration,
    viewOffset: viewOffset,
    lastViewedAt: lastViewedAt,
    viewCount: viewCount,
  );
}

enum StreamKind { video, audio, subtitle, other }

class MediaStream {
  /// The server's id for the track — what stream selection sends back.
  final int id;
  final StreamKind kind;
  final String? codec;
  final String? language;
  final String? languageCode;

  /// A sidecar subtitle's server-relative path, fetched as its own caption
  /// file (see MediaServerClient.subtitleUrl). Null for a track muxed into
  /// the container.
  final String? key;

  /// Position in the container.
  final int? index;

  /// The server's remembered choice for this file.
  final bool selected;
  final bool forced;

  /// The server's own summary, e.g. "4K DoVi/HDR10 (HEVC Main 10)" or
  /// "English (TRUEHD 7.1)" — what screen 03's media chips read HDR from.
  final String? displayTitle;
  final int? channels;

  /// Video streams only: e.g. 23.976, and the coded size — what the
  /// player's frame-rate matching picks a display mode from.
  final double? frameRate;
  final int? width;
  final int? height;

  const MediaStream({
    this.id = 0,
    required this.kind,
    this.codec,
    this.language,
    this.languageCode,
    this.key,
    this.index,
    this.selected = false,
    this.forced = false,
    this.displayTitle,
    this.channels,
    this.frameRate,
    this.width,
    this.height,
  });
}

/// One file of a [MediaVersion].
class MediaPart {
  final String id;

  /// The file's server-relative path, for backends that direct-play by
  /// path (Plex). Opaque above the client.
  final String key;
  final String? container;
  final int? duration;

  /// File size in bytes.
  final int? size;
  final List<MediaStream> streams;

  const MediaPart({
    required this.id,
    this.key = '',
    this.container,
    this.duration,
    this.size,
    this.streams = const [],
  });
}

/// One encoding of a title (a 4K and a 1080p file are two versions).
class MediaVersion {
  final String? videoCodec;
  final String? audioCodec;
  final String? container;

  /// "4k", "1080", "720", "sd".
  final String? videoResolution;
  final int? audioChannels;
  final List<MediaPart> parts;

  const MediaVersion({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.videoResolution,
    this.audioChannels,
    this.parts = const [],
  });
}

class Person {
  /// This server's id for the person — only meaningful on that server.
  final String? id;
  final String name;

  /// The character, for a cast entry.
  final String? role;
  final String? thumb;

  /// An id for the person that is the same on every server (Plex's
  /// `tagKey`), how the same person is found on another one.
  final String? globalId;

  const Person({this.id, required this.name, this.role, this.thumb, this.globalId});
}

class Review {
  final String tag;
  final String text;
  final String? source;
  final String? image;

  const Review({required this.tag, required this.text, this.source, this.image});
}

/// The full picture of one playable or browsable title — what detail pages,
/// the lobby and the player work from.
class MediaDetail {
  final String id;
  final MediaKind kind;
  final String title;
  final String? thumb;
  final String? art;
  final String? guid;
  final List<String> externalIds;
  final String? summary;
  final int? duration;
  final int? viewOffset;
  final String? studio;
  final String? contentRating;
  final int? year;

  /// Episode context (null for movies) — the player's "SHOW · S2 E4" kicker.
  final String? grandparentTitle;
  final int? parentIndex;
  final int? index;

  final List<MediaVersion> media;

  final double? rating;
  final double? audienceRating;
  final String? ratingImage;
  final String? audienceRatingImage;

  final List<Person> roles;
  final List<Person> directors;
  final List<Person> writers;
  final List<Review> reviews;

  const MediaDetail({
    required this.id,
    this.kind = MediaKind.other,
    required this.title,
    this.thumb,
    this.art,
    this.guid,
    this.externalIds = const [],
    this.summary,
    this.duration,
    this.viewOffset,
    this.studio,
    this.contentRating,
    this.year,
    this.grandparentTitle,
    this.parentIndex,
    this.index,
    this.media = const [],
    this.rating,
    this.audienceRating,
    this.ratingImage,
    this.audienceRatingImage,
    this.roles = const [],
    this.directors = const [],
    this.writers = const [],
    this.reviews = const [],
  });

  /// The "restart from beginning" (`viewOffset: 0`) case AppRoot needs.
  MediaDetail copyWith({int? viewOffset}) => MediaDetail(
    id: id,
    kind: kind,
    title: title,
    thumb: thumb,
    art: art,
    guid: guid,
    externalIds: externalIds,
    summary: summary,
    duration: duration,
    viewOffset: viewOffset ?? this.viewOffset,
    studio: studio,
    contentRating: contentRating,
    year: year,
    grandparentTitle: grandparentTitle,
    parentIndex: parentIndex,
    index: index,
    media: media,
    rating: rating,
    audienceRating: audienceRating,
    ratingImage: ratingImage,
    audienceRatingImage: audienceRatingImage,
    roles: roles,
    directors: directors,
    writers: writers,
    reviews: reviews,
  );
}

class MediaHub {
  final String? id;
  final String title;
  final List<MediaItem> items;

  const MediaHub({this.id, this.title = '', this.items = const []});
}
