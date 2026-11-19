import '../data/media/media_models.dart';
import '../data/media/media_server.dart';
import '../state/room_title.dart';
import 'relay_protocol.dart';

/// The host moving a Watch Together room on to another episode — what a
/// guest needs to find that episode on its own servers, whichever they are:
///
/// - the host's own item ([ratingKey] on [serverId]), for a guest sharing
///   the host's server;
/// - the show and the episode's place in it ([seasonIndex]/[episodeIndex]),
///   for a guest with its own copy of the show — found by the show it's
///   already playing, else by [showTitle] matched on [showIds];
/// - [title], the room's new name in the directory.
class EpisodeSwitch {
  const EpisodeSwitch({
    required this.title,
    required this.ratingKey,
    required this.serverId,
    required this.ids,
    required this.mediaTitle,
    required this.showTitle,
    required this.showIds,
    required this.seasonIndex,
    required this.episodeIndex,
  });

  static const kind = 'episodeSwitch';

  /// A guest's Next episode: it asks the host, who moves the whole room.
  static const nextRequestKind = 'next';

  final String title;
  final String ratingKey;
  final String serverId;
  final List<String> ids;
  final String mediaTitle;
  final String showTitle;
  final List<String> showIds;
  final int seasonIndex;
  final int episodeIndex;

  /// The switch to [episode] of [showTitle], on the host's [server].
  factory EpisodeSwitch.to(MediaDetail episode, MediaServer server, {required String showTitle, List<String> showIds = const []}) =>
      EpisodeSwitch(
        title: '$showTitle · S${episode.parentIndex}E${episode.index}',
        ratingKey: episode.id,
        serverId: server.id,
        ids: roomIdsFor(episode),
        mediaTitle: episode.title,
        showTitle: showTitle,
        showIds: showIds,
        seasonIndex: episode.parentIndex ?? 0,
        episodeIndex: episode.index ?? 0,
      );

  RelayEvent toEvent(String fromPeerId) => RelayEvent(
    kind: kind,
    fromPeerId: fromPeerId,
    title: title,
    ratingKey: ratingKey,
    serverId: serverId,
    ids: ids,
    mediaTitle: mediaTitle,
    showTitle: showTitle,
    showIds: showIds,
    seasonIndex: seasonIndex,
    episodeIndex: episodeIndex,
  );

  static EpisodeSwitch? fromEvent(RelayEvent e) {
    if (e.kind != kind) return null;
    final ratingKey = e.ratingKey, serverId = e.serverId, season = e.seasonIndex, episode = e.episodeIndex;
    if (ratingKey == null || serverId == null || season == null || episode == null) return null;
    return EpisodeSwitch(
      title: e.title ?? e.showTitle ?? '',
      ratingKey: ratingKey,
      serverId: serverId,
      ids: e.ids ?? const [],
      mediaTitle: e.mediaTitle ?? '',
      showTitle: e.showTitle ?? '',
      showIds: e.showIds ?? const [],
      seasonIndex: season,
      episodeIndex: episode,
    );
  }
}
