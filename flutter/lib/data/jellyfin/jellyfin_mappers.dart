import '../media/media_models.dart';

/// Jellyfin's wire format (`BaseItemDto` and friends, as plain JSON maps)
/// → the app's neutral models. Jellyfin times are ticks of 100 ns; the
/// neutral models are milliseconds.

typedef Json = Map<String, dynamic>;

/// Ticks (100 ns) to milliseconds.
int? ticksToMs(Object? ticks) => ticks is num ? ticks ~/ 10000 : null;

MediaKind jellyfinKind(String? type) => switch (type) {
  'Movie' => MediaKind.movie,
  'Series' => MediaKind.show,
  'Season' => MediaKind.season,
  'Episode' => MediaKind.episode,
  'BoxSet' => MediaKind.collection,
  _ => MediaKind.other,
};

MediaKind libraryKind(String? collectionType) => switch (collectionType) {
  'movies' => MediaKind.movie,
  'tvshows' => MediaKind.show,
  _ => MediaKind.other,
};

String _imagePath(String itemId, String type, String tag, {int? index}) =>
    '/Items/$itemId/Images/$type${index == null ? '' : '/$index'}?tag=$tag';

/// The item's poster (or an episode's still); a season or episode without
/// one borrows its show's.
String? posterPath(Json item) {
  final id = item['Id'] as String?;
  final tag = (item['ImageTags'] as Map?)?['Primary'] as String?;
  if (id != null && tag != null) return _imagePath(id, 'Primary', tag);
  final seriesId = item['SeriesId'] as String?;
  final seriesTag = item['SeriesPrimaryImageTag'] as String?;
  if (seriesId != null && seriesTag != null) {
    return _imagePath(seriesId, 'Primary', seriesTag);
  }
  return null;
}

/// The item's backdrop, else its parent's (an episode's show's).
String? backdropPath(Json item) {
  final id = item['Id'] as String?;
  final own = item['BackdropImageTags'] as List?;
  if (id != null && own != null && own.isNotEmpty) {
    return _imagePath(id, 'Backdrop', own.first as String, index: 0);
  }
  final parentId = item['ParentBackdropItemId'] as String?;
  final parent = item['ParentBackdropImageTags'] as List?;
  if (parentId != null && parent != null && parent.isNotEmpty) {
    return _imagePath(parentId, 'Backdrop', parent.first as String, index: 0);
  }
  return null;
}

/// `ProviderIds` normalised to the `imdb://…`/`tmdb://…`/`tvdb://…` form
/// Plex uses, so a copy on each folds into one card.
List<String> externalIds(Json item) {
  final ids = item['ProviderIds'] as Map?;
  if (ids == null) return const [];
  return [
    for (final MapEntry(:key, :value) in ids.entries)
      if (value is String && value.isNotEmpty)
        if (switch ('$key'.toLowerCase()) {
          'imdb' || 'tmdb' || 'tvdb' => true,
          _ => false,
        })
          '${'$key'.toLowerCase()}://$value',
  ];
}

int? _epochSeconds(Object? iso) {
  final at = iso is String ? DateTime.tryParse(iso) : null;
  return at == null ? null : at.millisecondsSinceEpoch ~/ 1000;
}

String? _date(Object? iso) =>
    iso is String && iso.length >= 10 ? iso.substring(0, 10) : null;

MediaLibrary libraryFromJson(Json view) => MediaLibrary(
  id: view['Id'] as String,
  title: view['Name'] as String? ?? '',
  kind: libraryKind(view['CollectionType'] as String?),
);

MediaItem itemFromJson(Json item) {
  final kind = jellyfinKind(item['Type'] as String?);
  final userData = item['UserData'] as Map?;
  final playCount = userData?['PlayCount'] as int?;
  return MediaItem(
    id: item['Id'] as String,
    kind: kind,
    title: item['Name'] as String? ?? '',
    parentTitle: switch (kind) {
      MediaKind.season => item['SeriesName'] as String?,
      MediaKind.episode => item['SeasonName'] as String?,
      _ => null,
    },
    parentId: kind == MediaKind.season ? item['SeriesId'] as String? : null,
    grandparentTitle: kind == MediaKind.episode
        ? item['SeriesName'] as String?
        : null,
    parentIndex: item['ParentIndexNumber'] as int?,
    index: item['IndexNumber'] as int?,
    year: item['ProductionYear'] as int?,
    thumb: posterPath(item),
    art: backdropPath(item),
    summary: item['Overview'] as String?,
    addedAt: _epochSeconds(item['DateCreated']),
    originallyAvailableAt: _date(item['PremiereDate']),
    contentRating: item['OfficialRating'] as String?,
    externalIds: externalIds(item),
    leafCount: kind == MediaKind.show
        ? item['RecursiveItemCount'] as int?
        : null,
    childCount: item['ChildCount'] as int?,
    genres: [for (final g in (item['Genres'] as List?) ?? const []) '$g'],
    duration: ticksToMs(item['RunTimeTicks']),
    viewOffset: ticksToMs(userData?['PlaybackPositionTicks']),
    viewCount: playCount ?? ((userData?['Played'] == true) ? 1 : 0),
  );
}

StreamKind _streamKind(String? type) => switch (type) {
  'Video' => StreamKind.video,
  'Audio' => StreamKind.audio,
  'Subtitle' => StreamKind.subtitle,
  _ => StreamKind.other,
};

MediaStream streamFromJson(Json s) => MediaStream(
  // Jellyfin selects tracks by their index in the container.
  id: s['Index'] as int? ?? 0,
  kind: _streamKind(s['Type'] as String?),
  codec: s['Codec'] as String?,
  language: s['DisplayLanguage'] as String? ?? s['Language'] as String?,
  languageCode: s['Language'] as String?,
  index: s['Index'] as int?,
  selected: s['IsDefault'] == true,
  forced: s['IsForced'] == true,
  displayTitle: s['DisplayTitle'] as String?,
  channels: s['Channels'] as int?,
  frameRate: (s['RealFrameRate'] as num?)?.toDouble(),
  width: s['Width'] as int?,
  height: s['Height'] as int?,
);

/// Plex's resolution buckets, from the video's coded width.
String? _resolution(int? width) => switch (width) {
  null => null,
  >= 3200 => '4k',
  >= 1800 => '1080',
  >= 1200 => '720',
  _ => 'sd',
};

MediaVersion versionFromJson(Json source) {
  final streams = [
    for (final s
        in ((source['MediaStreams'] as List?) ?? const []).cast<Json>())
      streamFromJson(s),
  ];
  final video = streams.where((s) => s.kind == StreamKind.video).firstOrNull;
  final audio =
      streams
          .where((s) => s.kind == StreamKind.audio && s.selected)
          .firstOrNull ??
      streams.where((s) => s.kind == StreamKind.audio).firstOrNull;
  return MediaVersion(
    videoCodec: video?.codec,
    audioCodec: audio?.codec,
    container: source['Container'] as String?,
    videoResolution: _resolution(video?.width),
    audioChannels: audio?.channels,
    parts: [
      MediaPart(
        id: source['Id'] as String? ?? '',
        container: source['Container'] as String?,
        duration: ticksToMs(source['RunTimeTicks']),
        size: source['Size'] as int?,
        streams: streams,
      ),
    ],
  );
}

Person personFromJson(Json p) {
  final id = p['Id'] as String?;
  final tag = p['PrimaryImageTag'] as String?;
  return Person(
    id: id,
    name: p['Name'] as String? ?? '',
    role: p['Type'] == 'Actor' ? p['Role'] as String? : null,
    thumb: id != null && tag != null ? _imagePath(id, 'Primary', tag) : null,
  );
}

MediaDetail detailFromJson(Json item) {
  final base = itemFromJson(item);
  final people = ((item['People'] as List?) ?? const []).cast<Json>();
  List<Person> ofType(String type) => [
    for (final p in people)
      if (p['Type'] == type) personFromJson(p),
  ];
  final studios = (item['Studios'] as List?)?.cast<Json>();
  final critic = item['CriticRating'] as num?;
  return MediaDetail(
    id: base.id,
    kind: base.kind,
    title: base.title,
    thumb: base.thumb,
    art: base.art,
    externalIds: base.externalIds,
    summary: base.summary,
    duration: base.duration,
    viewOffset: base.viewOffset,
    studio: studios?.firstOrNull?['Name'] as String?,
    contentRating: base.contentRating,
    year: base.year,
    grandparentTitle: base.grandparentTitle,
    parentIndex: base.parentIndex,
    index: base.index,
    media: [
      for (final s
          in ((item['MediaSources'] as List?) ?? const []).cast<Json>())
        versionFromJson(s),
    ],
    // Critics out of 100, the community out of 10 — Plex's scales.
    rating: critic == null ? null : critic / 10,
    audienceRating: (item['CommunityRating'] as num?)?.toDouble(),
    roles: ofType('Actor'),
    directors: ofType('Director'),
    writers: ofType('Writer'),
  );
}
