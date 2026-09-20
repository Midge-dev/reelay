import 'package:uuid/uuid.dart';

import '../data/plex/plex_models.dart';
import 'playback_decision.dart';

const _uuid = Uuid();

/// Ports PlexPlayerFactory.kt's URL-building formulas exactly — everything
/// except the ExoPlayer-specific `create`/`applySubtitleSelection` methods,
/// which have no Flutter equivalent (see [VideoPlayerSyncedPlayer] and
/// `resolveSubtitleSource` in playback_decision.dart for how subtitle
/// attachment is actually handled on this platform).
class PlexPlayerFactory {
  const PlexPlayerFactory._();

  static String directPlayUrl(PlexServer server, PlexPart part) => '${server.baseUrl}${part.key}?X-Plex-Token=${server.accessToken}';

  static String transcodeUrl(
    PlexServer server,
    Transcode decision,
    int maxVideoBitrateKbps, {
    String? sessionId,
  }) {
    final session = sessionId ?? _uuid.v4();
    final path = Uri.encodeComponent('${server.baseUrl}/library/metadata/${decision.ratingKey}');
    return '${server.baseUrl}/video/:/transcode/universal/start.m3u8'
        '?path=$path'
        '&mediaIndex=0&partIndex=0&protocol=hls'
        '&fastSeek=1&copyts=1&offset=0'
        '&directPlay=0&directStream=0'
        '&videoResolution=1920x1080&maxVideoBitrate=$maxVideoBitrateKbps'
        '&subtitleSize=100'
        '&subtitleStreamID=${decision.subtitleStreamId ?? 0}'
        '&session=$session'
        '&X-Plex-Token=${server.accessToken}';
  }

  static String mediaUrl(PlexServer server, PlaybackDecision decision, int maxVideoBitrateKbps, {String? sessionId}) {
    return switch (decision) {
      DirectPlay() => directPlayUrl(server, decision.part),
      Transcode() => transcodeUrl(server, decision, maxVideoBitrateKbps, sessionId: sessionId),
    };
  }
}
