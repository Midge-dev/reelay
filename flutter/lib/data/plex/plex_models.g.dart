// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plex_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlexConnection _$PlexConnectionFromJson(Map<String, dynamic> json) =>
    PlexConnection(
      uri: json['uri'] as String,
      local: json['local'] as bool? ?? false,
      relay: json['relay'] as bool? ?? false,
    );

Map<String, dynamic> _$PlexConnectionToJson(PlexConnection instance) =>
    <String, dynamic>{
      'uri': instance.uri,
      'local': instance.local,
      'relay': instance.relay,
    };

PlexResource _$PlexResourceFromJson(Map<String, dynamic> json) => PlexResource(
  name: json['name'] as String,
  provides: json['provides'] as String? ?? '',
  owned: json['owned'] as bool? ?? false,
  machineIdentifier: json['clientIdentifier'] as String? ?? '',
  accessToken: json['accessToken'] as String?,
  connections:
      (json['connections'] as List<dynamic>?)
          ?.map((e) => PlexConnection.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$PlexResourceToJson(PlexResource instance) =>
    <String, dynamic>{
      'name': instance.name,
      'provides': instance.provides,
      'owned': instance.owned,
      'clientIdentifier': instance.machineIdentifier,
      'accessToken': instance.accessToken,
      'connections': instance.connections,
    };

PlexSection _$PlexSectionFromJson(Map<String, dynamic> json) => PlexSection(
  key: json['key'] as String,
  title: json['title'] as String,
  type: json['type'] as String? ?? '',
  agent: json['agent'] as String? ?? '',
);

Map<String, dynamic> _$PlexSectionToJson(PlexSection instance) =>
    <String, dynamic>{
      'key': instance.key,
      'title': instance.title,
      'type': instance.type,
      'agent': instance.agent,
    };

PlexTag _$PlexTagFromJson(Map<String, dynamic> json) =>
    PlexTag(tag: json['tag'] as String);

Map<String, dynamic> _$PlexTagToJson(PlexTag instance) => <String, dynamic>{
  'tag': instance.tag,
};

PlexGuid _$PlexGuidFromJson(Map<String, dynamic> json) =>
    PlexGuid(id: json['id'] as String);

Map<String, dynamic> _$PlexGuidToJson(PlexGuid instance) => <String, dynamic>{
  'id': instance.id,
};

PlexLibraryItem _$PlexLibraryItemFromJson(Map<String, dynamic> json) =>
    PlexLibraryItem(
      ratingKey: json['ratingKey'] as String,
      type: json['type'] as String?,
      title: json['title'] as String,
      parentTitle: json['parentTitle'] as String?,
      parentRatingKey: json['parentRatingKey'] as String?,
      year: (json['year'] as num?)?.toInt(),
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      summary: json['summary'] as String?,
      addedAt: (json['addedAt'] as num?)?.toInt(),
      originallyAvailableAt: json['originallyAvailableAt'] as String?,
      guid: json['guid'] as String?,
      contentRating: json['contentRating'] as String?,
      leafCount: (json['leafCount'] as num?)?.toInt(),
      childCount: (json['childCount'] as num?)?.toInt(),
      guids:
          (json['Guid'] as List<dynamic>?)
              ?.map((e) => PlexGuid.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      genres:
          (json['Genre'] as List<dynamic>?)
              ?.map((e) => PlexTag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      collections:
          (json['Collection'] as List<dynamic>?)
              ?.map((e) => PlexTag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PlexLibraryItemToJson(PlexLibraryItem instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'type': instance.type,
      'title': instance.title,
      'parentTitle': instance.parentTitle,
      'parentRatingKey': instance.parentRatingKey,
      'year': instance.year,
      'thumb': instance.thumb,
      'art': instance.art,
      'summary': instance.summary,
      'addedAt': instance.addedAt,
      'originallyAvailableAt': instance.originallyAvailableAt,
      'guid': instance.guid,
      'contentRating': instance.contentRating,
      'leafCount': instance.leafCount,
      'childCount': instance.childCount,
      'Genre': instance.genres,
      'Collection': instance.collections,
      'Guid': instance.guids,
    };

PlexWatchlistItem _$PlexWatchlistItemFromJson(Map<String, dynamic> json) =>
    PlexWatchlistItem(
      ratingKey: json['ratingKey'] as String,
      type: json['type'] as String?,
      title: json['title'] as String,
      thumb: json['thumb'] as String?,
      year: (json['year'] as num?)?.toInt(),
      guid: json['guid'] as String?,
      addedAt: (json['addedAt'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PlexWatchlistItemToJson(PlexWatchlistItem instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'type': instance.type,
      'title': instance.title,
      'thumb': instance.thumb,
      'year': instance.year,
      'guid': instance.guid,
      'addedAt': instance.addedAt,
    };

PlexCollection _$PlexCollectionFromJson(Map<String, dynamic> json) =>
    PlexCollection(
      ratingKey: json['ratingKey'] as String,
      title: json['title'] as String,
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      childCount: (json['childCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PlexCollectionToJson(PlexCollection instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'title': instance.title,
      'thumb': instance.thumb,
      'art': instance.art,
      'childCount': instance.childCount,
    };

PlexSeason _$PlexSeasonFromJson(Map<String, dynamic> json) => PlexSeason(
  ratingKey: json['ratingKey'] as String,
  title: json['title'] as String,
  index: (json['index'] as num?)?.toInt(),
  thumb: json['thumb'] as String?,
);

Map<String, dynamic> _$PlexSeasonToJson(PlexSeason instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'title': instance.title,
      'index': instance.index,
      'thumb': instance.thumb,
    };

PlexEpisode _$PlexEpisodeFromJson(Map<String, dynamic> json) => PlexEpisode(
  ratingKey: json['ratingKey'] as String,
  title: json['title'] as String,
  index: (json['index'] as num?)?.toInt(),
  thumb: json['thumb'] as String?,
  summary: json['summary'] as String?,
  duration: (json['duration'] as num?)?.toInt(),
  viewOffset: (json['viewOffset'] as num?)?.toInt(),
  parentIndex: (json['parentIndex'] as num?)?.toInt(),
  grandparentTitle: json['grandparentTitle'] as String?,
  originallyAvailableAt: json['originallyAvailableAt'] as String?,
  viewCount: (json['viewCount'] as num?)?.toInt(),
);

Map<String, dynamic> _$PlexEpisodeToJson(PlexEpisode instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'title': instance.title,
      'index': instance.index,
      'thumb': instance.thumb,
      'summary': instance.summary,
      'duration': instance.duration,
      'viewOffset': instance.viewOffset,
      'parentIndex': instance.parentIndex,
      'grandparentTitle': instance.grandparentTitle,
      'originallyAvailableAt': instance.originallyAvailableAt,
      'viewCount': instance.viewCount,
    };

PlexStream _$PlexStreamFromJson(Map<String, dynamic> json) => PlexStream(
  id: (json['id'] as num?)?.toInt() ?? 0,
  streamType: (json['streamType'] as num).toInt(),
  displayTitle: json['displayTitle'] as String?,
  channels: (json['channels'] as num?)?.toInt(),
  codec: json['codec'] as String?,
  language: json['language'] as String?,
  languageCode: json['languageCode'] as String?,
  key: json['key'] as String?,
  index: (json['index'] as num?)?.toInt(),
  selected: json['selected'] as bool? ?? false,
  forced: json['forced'] as bool? ?? false,
);

Map<String, dynamic> _$PlexStreamToJson(PlexStream instance) =>
    <String, dynamic>{
      'id': instance.id,
      'streamType': instance.streamType,
      'codec': instance.codec,
      'language': instance.language,
      'languageCode': instance.languageCode,
      'key': instance.key,
      'index': instance.index,
      'selected': instance.selected,
      'forced': instance.forced,
      'displayTitle': instance.displayTitle,
      'channels': instance.channels,
    };

PlexPart _$PlexPartFromJson(Map<String, dynamic> json) => PlexPart(
  id: (json['id'] as num).toInt(),
  key: json['key'] as String,
  size: (json['size'] as num?)?.toInt(),
  container: json['container'] as String?,
  duration: (json['duration'] as num?)?.toInt(),
  streams:
      (json['Stream'] as List<dynamic>?)
          ?.map((e) => PlexStream.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$PlexPartToJson(PlexPart instance) => <String, dynamic>{
  'id': instance.id,
  'key': instance.key,
  'container': instance.container,
  'duration': instance.duration,
  'size': instance.size,
  'Stream': instance.streams,
};

PlexMedia _$PlexMediaFromJson(Map<String, dynamic> json) => PlexMedia(
  audioChannels: (json['audioChannels'] as num?)?.toInt(),
  videoCodec: json['videoCodec'] as String?,
  audioCodec: json['audioCodec'] as String?,
  container: json['container'] as String?,
  videoResolution: json['videoResolution'] as String?,
  parts:
      (json['Part'] as List<dynamic>?)
          ?.map((e) => PlexPart.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$PlexMediaToJson(PlexMedia instance) => <String, dynamic>{
  'videoCodec': instance.videoCodec,
  'audioCodec': instance.audioCodec,
  'container': instance.container,
  'videoResolution': instance.videoResolution,
  'audioChannels': instance.audioChannels,
  'Part': instance.parts,
};

PlexPerson _$PlexPersonFromJson(Map<String, dynamic> json) => PlexPerson(
  id: (json['id'] as num?)?.toInt(),
  tag: json['tag'] as String,
  role: json['role'] as String?,
  thumb: json['thumb'] as String?,
  tagKey: json['tagKey'] as String?,
);

Map<String, dynamic> _$PlexPersonToJson(PlexPerson instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tag': instance.tag,
      'role': instance.role,
      'thumb': instance.thumb,
      'tagKey': instance.tagKey,
    };

PlexReview _$PlexReviewFromJson(Map<String, dynamic> json) => PlexReview(
  tag: json['tag'] as String,
  text: json['text'] as String,
  source: json['source'] as String?,
  image: json['image'] as String?,
);

Map<String, dynamic> _$PlexReviewToJson(PlexReview instance) =>
    <String, dynamic>{
      'tag': instance.tag,
      'text': instance.text,
      'source': instance.source,
      'image': instance.image,
    };

PlexMovieDetail _$PlexMovieDetailFromJson(Map<String, dynamic> json) =>
    PlexMovieDetail(
      ratingKey: json['ratingKey'] as String,
      title: json['title'] as String,
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      guid: json['guid'] as String?,
      summary: json['summary'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      viewOffset: (json['viewOffset'] as num?)?.toInt(),
      studio: json['studio'] as String?,
      contentRating: json['contentRating'] as String?,
      year: (json['year'] as num?)?.toInt(),
      grandparentTitle: json['grandparentTitle'] as String?,
      parentIndex: (json['parentIndex'] as num?)?.toInt(),
      index: (json['index'] as num?)?.toInt(),
      media:
          (json['Media'] as List<dynamic>?)
              ?.map((e) => PlexMedia.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      rating: (json['rating'] as num?)?.toDouble(),
      audienceRating: (json['audienceRating'] as num?)?.toDouble(),
      ratingImage: json['ratingImage'] as String?,
      audienceRatingImage: json['audienceRatingImage'] as String?,
      roles:
          (json['Role'] as List<dynamic>?)
              ?.map((e) => PlexPerson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      directors:
          (json['Director'] as List<dynamic>?)
              ?.map((e) => PlexPerson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      writers:
          (json['Writer'] as List<dynamic>?)
              ?.map((e) => PlexPerson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      reviews:
          (json['Review'] as List<dynamic>?)
              ?.map((e) => PlexReview.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PlexMovieDetailToJson(PlexMovieDetail instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'title': instance.title,
      'thumb': instance.thumb,
      'art': instance.art,
      'guid': instance.guid,
      'summary': instance.summary,
      'duration': instance.duration,
      'viewOffset': instance.viewOffset,
      'studio': instance.studio,
      'contentRating': instance.contentRating,
      'year': instance.year,
      'grandparentTitle': instance.grandparentTitle,
      'parentIndex': instance.parentIndex,
      'index': instance.index,
      'Media': instance.media,
      'rating': instance.rating,
      'audienceRating': instance.audienceRating,
      'ratingImage': instance.ratingImage,
      'audienceRatingImage': instance.audienceRatingImage,
      'Role': instance.roles,
      'Director': instance.directors,
      'Writer': instance.writers,
      'Review': instance.reviews,
    };

PlexOnDeckItem _$PlexOnDeckItemFromJson(Map<String, dynamic> json) =>
    PlexOnDeckItem(
      ratingKey: json['ratingKey'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      viewOffset: (json['viewOffset'] as num?)?.toInt(),
      grandparentTitle: json['grandparentTitle'] as String?,
      parentIndex: (json['parentIndex'] as num?)?.toInt(),
      index: (json['index'] as num?)?.toInt(),
      guid: json['guid'] as String?,
      summary: json['summary'] as String?,
      year: (json['year'] as num?)?.toInt(),
      childCount: (json['childCount'] as num?)?.toInt(),
      guids:
          (json['Guid'] as List<dynamic>?)
              ?.map((e) => PlexGuid.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PlexOnDeckItemToJson(PlexOnDeckItem instance) =>
    <String, dynamic>{
      'ratingKey': instance.ratingKey,
      'type': instance.type,
      'title': instance.title,
      'thumb': instance.thumb,
      'art': instance.art,
      'duration': instance.duration,
      'viewOffset': instance.viewOffset,
      'grandparentTitle': instance.grandparentTitle,
      'parentIndex': instance.parentIndex,
      'index': instance.index,
      'guid': instance.guid,
      'summary': instance.summary,
      'year': instance.year,
      'childCount': instance.childCount,
      'Guid': instance.guids,
    };

PlexHub _$PlexHubFromJson(Map<String, dynamic> json) => PlexHub(
  hubIdentifier: json['hubIdentifier'] as String?,
  title: json['title'] as String? ?? '',
  items:
      (json['Metadata'] as List<dynamic>?)
          ?.map((e) => PlexOnDeckItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$PlexHubToJson(PlexHub instance) => <String, dynamic>{
  'hubIdentifier': instance.hubIdentifier,
  'title': instance.title,
  'Metadata': instance.items,
};
