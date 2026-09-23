import 'package:json_annotation/json_annotation.dart';

part 'plex_models.g.dart';

@JsonSerializable()
class PlexConnection {
  final String uri;
  final bool local;
  final bool relay;

  const PlexConnection({required this.uri, this.local = false, this.relay = false});

  factory PlexConnection.fromJson(Map<String, dynamic> json) => _$PlexConnectionFromJson(json);
  Map<String, dynamic> toJson() => _$PlexConnectionToJson(this);
}

@JsonSerializable()
class PlexResource {
  final String name;
  final String provides;
  final bool owned;

  @JsonKey(name: 'clientIdentifier')
  final String machineIdentifier;

  final String? accessToken;
  final List<PlexConnection> connections;

  const PlexResource({
    required this.name,
    this.provides = '',
    this.owned = false,
    this.machineIdentifier = '',
    this.accessToken,
    this.connections = const [],
  });

  factory PlexResource.fromJson(Map<String, dynamic> json) => _$PlexResourceFromJson(json);
  Map<String, dynamic> toJson() => _$PlexResourceToJson(this);
}

class PlexServer {
  final String name;
  final String baseUrl;
  final String accessToken;

  /// Stable per-server id (Plex's `machineIdentifier`, from [PlexResource]) —
  /// survives IP/URL changes, unlike [baseUrl]. Empty for servers built
  /// without one (e.g. older test fixtures); the multi-server hub uses this
  /// to key connected/disabled servers, so real connections always set it.
  final String machineIdentifier;

  const PlexServer({
    required this.name,
    required this.baseUrl,
    required this.accessToken,
    this.machineIdentifier = '',
  });
}

@JsonSerializable()
class PlexSection {
  final String key;
  final String title;
  final String type;

  /// The library's metadata agent. Plex's "Other Videos"/home-video
  /// libraries use a `*.agents.none` agent — no matching, no posters, no
  /// ids to fold on — which is how [isBrowsable] tells them apart from a
  /// real Movies/Shows library without guessing from the title.
  final String agent;

  const PlexSection({required this.key, required this.title, this.type = '', this.agent = ''});

  /// A movie or show library with a real metadata agent — the only kind
  /// the rail and home rows surface.
  bool get isBrowsable => (type == 'movie' || type == 'show') && !agent.endsWith('.none');

  factory PlexSection.fromJson(Map<String, dynamic> json) => _$PlexSectionFromJson(json);
  Map<String, dynamic> toJson() => _$PlexSectionToJson(this);
}

@JsonSerializable()
class PlexTag {
  final String tag;

  const PlexTag({required this.tag});

  factory PlexTag.fromJson(Map<String, dynamic> json) => _$PlexTagFromJson(json);
  Map<String, dynamic> toJson() => _$PlexTagToJson(this);
}

/// One entry of Plex's `Guid` array — `imdb://tt.../tmdb://.../tvdb://...`,
/// present on modern agents regardless of which one is the server's
/// *primary* agent (that's the scalar [PlexLibraryItem.guid]/
/// [PlexOnDeckItem.guid] instead, which can differ across two servers
/// indexing the same title under different agents). duplicate_fold.dart's
/// [foldByGuid] matches on either, so two copies fold together the moment
/// they agree on any one provider id, not only on an identical primary
/// agent.
@JsonSerializable()
class PlexGuid {
  final String id;

  const PlexGuid({required this.id});

  factory PlexGuid.fromJson(Map<String, dynamic> json) => _$PlexGuidFromJson(json);
  Map<String, dynamic> toJson() => _$PlexGuidToJson(this);
}

@JsonSerializable()
class PlexLibraryItem {
  final String ratingKey;
  final String? type;
  final String title;
  final String? parentTitle;
  final String? parentRatingKey;
  final int? year;
  final String? thumb;
  final String? art;
  final String? summary;
  final int? addedAt;
  final String? originallyAvailableAt;
  final String? guid;
  final String? contentRating;

  /// Total episode count on a show item (Plex's own rollup) — the season
  /// count is not carried here since it's just `seasons.length` once a
  /// show detail screen has actually loaded them.
  final int? leafCount;

  @JsonKey(name: 'Genre', defaultValue: [])
  final List<PlexTag> genres;

  @JsonKey(name: 'Collection', defaultValue: [])
  final List<PlexTag> collections;

  @JsonKey(name: 'Guid', defaultValue: [])
  final List<PlexGuid> guids;

  const PlexLibraryItem({
    required this.ratingKey,
    this.type,
    required this.title,
    this.parentTitle,
    this.parentRatingKey,
    this.year,
    this.thumb,
    this.art,
    this.summary,
    this.addedAt,
    this.originallyAvailableAt,
    this.guid,
    this.contentRating,
    this.leafCount,
    this.guids = const [],
    this.genres = const [],
    this.collections = const [],
  });

  factory PlexLibraryItem.fromJson(Map<String, dynamic> json) => _$PlexLibraryItemFromJson(json);
  Map<String, dynamic> toJson() => _$PlexLibraryItemToJson(this);
}

/// A Discover-universe watchlist entry from `discover.provider.plex.tv` —
/// distinct from any local server's [PlexLibraryItem].
@JsonSerializable()
class PlexWatchlistItem {
  final String ratingKey;
  final String? type;
  final String title;
  final String? thumb;
  final int? year;
  final String? guid;
  final int? addedAt;

  const PlexWatchlistItem({
    required this.ratingKey,
    this.type,
    required this.title,
    this.thumb,
    this.year,
    this.guid,
    this.addedAt,
  });

  factory PlexWatchlistItem.fromJson(Map<String, dynamic> json) => _$PlexWatchlistItemFromJson(json);
  Map<String, dynamic> toJson() => _$PlexWatchlistItemToJson(this);
}

@JsonSerializable()
class PlexCollection {
  final String ratingKey;
  final String title;
  final String? thumb;
  final String? art;
  final int? childCount;

  const PlexCollection({
    required this.ratingKey,
    required this.title,
    this.thumb,
    this.art,
    this.childCount,
  });

  factory PlexCollection.fromJson(Map<String, dynamic> json) => _$PlexCollectionFromJson(json);
  Map<String, dynamic> toJson() => _$PlexCollectionToJson(this);
}

@JsonSerializable()
class PlexSeason {
  final String ratingKey;
  final String title;
  final int? index;
  final String? thumb;

  const PlexSeason({required this.ratingKey, required this.title, this.index, this.thumb});

  factory PlexSeason.fromJson(Map<String, dynamic> json) => _$PlexSeasonFromJson(json);
  Map<String, dynamic> toJson() => _$PlexSeasonToJson(this);
}

@JsonSerializable()
class PlexEpisode {
  final String ratingKey;
  final String title;
  final int? index;
  final String? thumb;
  final String? summary;
  final int? duration;
  final int? viewOffset;
  final int? parentIndex;
  final String? grandparentTitle;
  final String? originallyAvailableAt;

  const PlexEpisode({
    required this.ratingKey,
    required this.title,
    this.index,
    this.thumb,
    this.summary,
    this.duration,
    this.viewOffset,
    this.parentIndex,
    this.grandparentTitle,
    this.originallyAvailableAt,
  });

  factory PlexEpisode.fromJson(Map<String, dynamic> json) => _$PlexEpisodeFromJson(json);
  Map<String, dynamic> toJson() => _$PlexEpisodeToJson(this);
}

@JsonSerializable()
class PlexStream {
  final int id;
  final int streamType;
  final String? codec;
  final String? language;
  final String? languageCode;
  final String? key;
  final int? index;
  final bool selected;
  final bool forced;

  const PlexStream({
    this.id = 0,
    required this.streamType,
    this.codec,
    this.language,
    this.languageCode,
    this.key,
    this.index,
    this.selected = false,
    this.forced = false,
  });

  factory PlexStream.fromJson(Map<String, dynamic> json) => _$PlexStreamFromJson(json);
  Map<String, dynamic> toJson() => _$PlexStreamToJson(this);
}

@JsonSerializable()
class PlexPart {
  final int id;
  final String key;
  final String? container;
  final int? duration;

  @JsonKey(name: 'Stream', defaultValue: [])
  final List<PlexStream> streams;

  const PlexPart({
    required this.id,
    required this.key,
    this.container,
    this.duration,
    this.streams = const [],
  });

  factory PlexPart.fromJson(Map<String, dynamic> json) => _$PlexPartFromJson(json);
  Map<String, dynamic> toJson() => _$PlexPartToJson(this);
}

@JsonSerializable()
class PlexMedia {
  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final String? videoResolution;

  @JsonKey(name: 'Part', defaultValue: [])
  final List<PlexPart> parts;

  const PlexMedia({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.videoResolution,
    this.parts = const [],
  });

  factory PlexMedia.fromJson(Map<String, dynamic> json) => _$PlexMediaFromJson(json);
  Map<String, dynamic> toJson() => _$PlexMediaToJson(this);
}

@JsonSerializable()
class PlexPerson {
  final int? id;
  final String tag;
  final String? role;
  final String? thumb;

  const PlexPerson({this.id, required this.tag, this.role, this.thumb});

  factory PlexPerson.fromJson(Map<String, dynamic> json) => _$PlexPersonFromJson(json);
  Map<String, dynamic> toJson() => _$PlexPersonToJson(this);
}

@JsonSerializable()
class PlexReview {
  final String tag;
  final String text;
  final String? source;
  final String? image;

  const PlexReview({required this.tag, required this.text, this.source, this.image});

  factory PlexReview.fromJson(Map<String, dynamic> json) => _$PlexReviewFromJson(json);
  Map<String, dynamic> toJson() => _$PlexReviewToJson(this);
}

@JsonSerializable()
class PlexMovieDetail {
  final String ratingKey;
  final String title;
  final String? thumb;
  final String? art;
  final String? guid;
  final String? summary;
  final int? duration;
  final int? viewOffset;

  @JsonKey(name: 'Media', defaultValue: [])
  final List<PlexMedia> media;

  final double? rating;
  final double? audienceRating;
  final String? ratingImage;
  final String? audienceRatingImage;

  @JsonKey(name: 'Role', defaultValue: [])
  final List<PlexPerson> roles;

  @JsonKey(name: 'Director', defaultValue: [])
  final List<PlexPerson> directors;

  @JsonKey(name: 'Writer', defaultValue: [])
  final List<PlexPerson> writers;

  @JsonKey(name: 'Review', defaultValue: [])
  final List<PlexReview> reviews;

  const PlexMovieDetail({
    required this.ratingKey,
    required this.title,
    this.thumb,
    this.art,
    this.guid,
    this.summary,
    this.duration,
    this.viewOffset,
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

  factory PlexMovieDetail.fromJson(Map<String, dynamic> json) => _$PlexMovieDetailFromJson(json);
  Map<String, dynamic> toJson() => _$PlexMovieDetailToJson(this);

  /// json_serializable doesn't generate a `copyWith` — added by hand for
  /// the "restart from beginning" (`viewOffset: 0`) case AppRoot needs.
  PlexMovieDetail copyWith({int? viewOffset}) => PlexMovieDetail(
        ratingKey: ratingKey,
        title: title,
        thumb: thumb,
        art: art,
        guid: guid,
        summary: summary,
        duration: duration,
        viewOffset: viewOffset ?? this.viewOffset,
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

@JsonSerializable()
class PlexOnDeckItem {
  final String ratingKey;
  final String type;
  final String title;
  final String? thumb;
  final String? art;
  final int? duration;
  final int? viewOffset;
  final String? grandparentTitle;
  final int? parentIndex;
  final int? index;
  final String? guid;

  /// Episode or movie synopsis — the hero's body line (screen 01).
  final String? summary;

  @JsonKey(name: 'Guid', defaultValue: [])
  final List<PlexGuid> guids;

  const PlexOnDeckItem({
    required this.ratingKey,
    required this.type,
    required this.title,
    this.thumb,
    this.art,
    this.duration,
    this.viewOffset,
    this.grandparentTitle,
    this.parentIndex,
    this.index,
    this.guid,
    this.summary,
    this.guids = const [],
  });

  factory PlexOnDeckItem.fromJson(Map<String, dynamic> json) => _$PlexOnDeckItemFromJson(json);
  Map<String, dynamic> toJson() => _$PlexOnDeckItemToJson(this);
}

@JsonSerializable()
class PlexHub {
  final String? hubIdentifier;
  final String title;

  @JsonKey(name: 'Metadata', defaultValue: [])
  final List<PlexOnDeckItem> items;

  const PlexHub({this.hubIdentifier, this.title = '', this.items = const []});

  factory PlexHub.fromJson(Map<String, dynamic> json) => _$PlexHubFromJson(json);
  Map<String, dynamic> toJson() => _$PlexHubToJson(this);
}
