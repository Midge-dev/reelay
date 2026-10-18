import '../media/media_models.dart';
import 'plex_models.dart';

/// Plex's wire models → the app's neutral ones. Plex's `Guid` ids are
/// already in the normalised `imdb://…`/`tmdb://…`/`tvdb://…` form
/// [MediaItem.externalIds] uses.

MediaKind plexKind(String? type) => switch (type) {
  'movie' => MediaKind.movie,
  'show' => MediaKind.show,
  'season' => MediaKind.season,
  'episode' => MediaKind.episode,
  'collection' => MediaKind.collection,
  _ => MediaKind.other,
};

StreamKind _streamKind(int streamType) => switch (streamType) {
  1 => StreamKind.video,
  2 => StreamKind.audio,
  3 => StreamKind.subtitle,
  _ => StreamKind.other,
};

List<String> _ids(List<PlexGuid> guids) => [for (final g in guids) g.id];

extension PlexSectionToMedia on PlexSection {
  MediaLibrary toMedia() => MediaLibrary(id: key, title: title, kind: plexKind(type));
}

extension PlexLibraryItemToMedia on PlexLibraryItem {
  MediaItem toMedia() => MediaItem(
    id: ratingKey,
    kind: plexKind(type),
    title: title,
    parentTitle: parentTitle,
    parentId: parentRatingKey,
    year: year,
    thumb: thumb,
    art: art,
    summary: summary,
    addedAt: addedAt,
    originallyAvailableAt: originallyAvailableAt,
    guid: guid,
    externalIds: _ids(guids),
    contentRating: contentRating,
    leafCount: leafCount,
    childCount: childCount,
    genres: [for (final g in genres) g.tag],
    collections: [for (final c in collections) c.tag],
  );
}

extension PlexOnDeckItemToMedia on PlexOnDeckItem {
  MediaItem toMedia() => MediaItem(
    id: ratingKey,
    kind: plexKind(type),
    title: title,
    thumb: thumb,
    art: art,
    duration: duration,
    viewOffset: viewOffset,
    lastViewedAt: lastViewedAt,
    grandparentTitle: grandparentTitle,
    parentIndex: parentIndex,
    index: index,
    guid: guid,
    externalIds: _ids(guids),
    summary: summary,
    year: year,
    childCount: childCount,
  );
}

extension PlexWatchlistItemToMedia on PlexWatchlistItem {
  MediaItem toMedia() => MediaItem(
    id: ratingKey,
    kind: plexKind(type),
    title: title,
    thumb: thumb,
    year: year,
    guid: guid,
    addedAt: addedAt,
  );
}

extension PlexCollectionToMedia on PlexCollection {
  MediaItem toMedia() => MediaItem(
    id: ratingKey,
    kind: MediaKind.collection,
    title: title,
    thumb: thumb,
    art: art,
    childCount: childCount,
  );
}

extension PlexSeasonToMedia on PlexSeason {
  MediaItem toMedia() => MediaItem(id: ratingKey, kind: MediaKind.season, title: title, index: index, thumb: thumb);
}

extension PlexEpisodeToMedia on PlexEpisode {
  MediaItem toMedia() => MediaItem(
    id: ratingKey,
    kind: MediaKind.episode,
    title: title,
    index: index,
    thumb: thumb,
    summary: summary,
    duration: duration,
    viewOffset: viewOffset,
    parentIndex: parentIndex,
    grandparentTitle: grandparentTitle,
    originallyAvailableAt: originallyAvailableAt,
    viewCount: viewCount,
  );
}

extension PlexStreamToMedia on PlexStream {
  MediaStream toMedia() => MediaStream(
    id: id,
    kind: _streamKind(streamType),
    codec: codec,
    language: language,
    languageCode: languageCode,
    key: key,
    index: index,
    selected: selected,
    forced: forced,
    displayTitle: displayTitle,
    channels: channels,
    frameRate: frameRate,
    width: width,
    height: height,
  );
}

extension PlexPartToMedia on PlexPart {
  MediaPart toMedia() => MediaPart(
    id: '$id',
    key: key,
    container: container,
    duration: duration,
    size: size,
    streams: [for (final s in streams) s.toMedia()],
  );
}

extension PlexMediaToMedia on PlexMedia {
  MediaVersion toMedia() => MediaVersion(
    videoCodec: videoCodec,
    audioCodec: audioCodec,
    container: container,
    videoResolution: videoResolution,
    audioChannels: audioChannels,
    parts: [for (final p in parts) p.toMedia()],
  );
}

extension PlexPersonToMedia on PlexPerson {
  Person toMedia() => Person(id: id?.toString(), name: tag, role: role, thumb: thumb, globalId: tagKey);
}

extension PlexReviewToMedia on PlexReview {
  Review toMedia() => Review(tag: tag, text: text, source: source, image: image);
}

extension PlexMovieDetailToMedia on PlexMovieDetail {
  MediaDetail toMedia() => MediaDetail(
    id: ratingKey,
    kind: plexKind(type),
    title: title,
    thumb: thumb,
    art: art,
    guid: guid,
    externalIds: _ids(guids),
    summary: summary,
    duration: duration,
    viewOffset: viewOffset,
    studio: studio,
    contentRating: contentRating,
    year: year,
    grandparentTitle: grandparentTitle,
    parentIndex: parentIndex,
    index: index,
    media: [for (final m in media) m.toMedia()],
    rating: rating,
    audienceRating: audienceRating,
    ratingImage: ratingImage,
    audienceRatingImage: audienceRatingImage,
    roles: [for (final p in roles) p.toMedia()],
    directors: [for (final p in directors) p.toMedia()],
    writers: [for (final p in writers) p.toMedia()],
    reviews: [for (final r in reviews) r.toMedia()],
  );
}

extension PlexHubToMedia on PlexHub {
  MediaHub toMedia() => MediaHub(id: hubIdentifier, title: title, items: [for (final i in items) i.toMedia()]);
}
