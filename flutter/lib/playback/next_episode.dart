import 'package:collection/collection.dart';

import '../data/media/media_models.dart';
import '../data/media/media_server_client.dart';

/// The episode of [showId] numbered [season]/[episode] on this server —
/// how a guest finds a room's next episode in its own copy of the show,
/// whatever ids its server gave it.
Future<MediaItem?> episodeNumbered(
  MediaServerClient client,
  String showId, {
  required int season,
  required int episode,
}) async {
  final seasons = await client.fetchSeasons(showId);
  final match = seasons.firstWhereOrNull((s) => s.index == season);
  if (match == null) return null;
  final episodes = await client.fetchEpisodes(match.id);
  return episodes.firstWhereOrNull((e) => e.index == episode);
}

/// The episode after [season]/[episode] of [showId]: the next one in its
/// season, else the first of the next season. Specials (season 0) are only
/// next after another special. Null after the last episode.
///
/// Worked out from the numbering rather than asked of the server's "next
/// up": that answers with the first episode not yet watched, which for the
/// one still playing is that same episode.
Future<MediaItem?> episodeAfter(
  MediaServerClient client,
  String showId, {
  required int season,
  required int episode,
}) async {
  final seasons = (await client.fetchSeasons(showId)).where((s) => s.index != null).toList()
    ..sort((a, b) => a.index!.compareTo(b.index!));
  final ordered = [
    ...seasons.where((s) => s.index == season),
    ...seasons.where((s) => s.index! > season && (season == 0 || s.index! > 0)),
  ];
  for (final s in ordered) {
    final episodes = (await client.fetchEpisodes(s.id)).where((e) => e.index != null).toList()
      ..sort((a, b) => a.index!.compareTo(b.index!));
    final next = s.index == season
        ? episodes.firstWhereOrNull((e) => e.index! > episode)
        : episodes.firstOrNull;
    if (next != null) return next;
  }
  return null;
}

/// [episodeAfter] for what's playing, when it's an episode of a known show.
Future<MediaItem?> episodeAfterDetail(MediaServerClient client, MediaDetail detail, {String? showId}) async {
  final show = detail.showId ?? showId;
  final season = detail.parentIndex;
  final episode = detail.index;
  if (show == null || season == null || episode == null) return null;
  return episodeAfter(client, show, season: season, episode: episode);
}
