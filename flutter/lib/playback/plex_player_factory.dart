import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/plex/plex_models.dart';
import 'playback_decision.dart';

const _uuid = Uuid();

/// The X-Plex-Platform Reelay reports — Plex keys its transcoder client
/// profiles off this.
String get _plexPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => 'tvOS',
  TargetPlatform.macOS => 'macOS',
  _ => 'Android',
};

/// Builds Plex's direct-play and transcode URLs. Subtitle attachment lives
/// elsewhere — see [VideoPlayerSyncedPlayer] and `resolveSubtitleSource` in
/// playback_decision.dart.
class PlexPlayerFactory {
  const PlexPlayerFactory._();

  static String directPlayUrl(PlexServer server, PlexPart part) =>
      '${server.baseUrl}${part.key}?X-Plex-Token=${server.accessToken}';

  // offsetMs tells Plex where in the source to *start encoding* — the
  // returned HLS stream's own position 0 IS offsetMs into the original
  // file. A client-side seekTo() after opening this URL is not just
  // redundant but actively wrong: it asks for a position Plex's transcode
  // session was never told about and hasn't produced segments for, which
  // 400s (see project notes on the CC-cycle-mid-playback crash this fixed).
  //
  // The X-Plex-* identity params are required: with no platform or profile
  // name, PMS logs "Unable to find client profile for device" and 400s the
  // request. `Generic` is PMS's built-in profile for a plain HLS client.
  static String transcodeUrl(
    PlexServer server,
    Transcode decision,
    int maxVideoBitrateKbps, {
    required String clientIdentifier,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  }) {
    final session = sessionId ?? _uuid.v4();
    final path = Uri.encodeComponent(
      '${server.baseUrl}/library/metadata/${decision.ratingKey}',
    );
    final offsetSeconds = offsetMs ~/ 1000;
    return '${server.baseUrl}/video/:/transcode/universal/start.m3u8'
        '?path=$path'
        '&mediaIndex=0&partIndex=0&protocol=hls'
        '&fastSeek=1&copyts=1&offset=$offsetSeconds'
        '&directPlay=0&directStream=0'
        '&videoResolution=1920x1080&maxVideoBitrate=$maxVideoBitrateKbps'
        '&subtitleSize=100'
        '&subtitles=${decision.subtitleStreamId != null ? 'burn' : 'none'}'
        '&subtitleStreamID=${decision.subtitleStreamId ?? 0}'
        '&session=$session'
        '&X-Plex-Product=Reelay'
        '&X-Plex-Platform=$_plexPlatform'
        '&X-Plex-Client-Profile-Name=Generic'
        '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(clientIdentifier)}'
        '&X-Plex-Session-Identifier=${Uri.encodeQueryComponent(sessionIdentifier)}'
        '&X-Plex-Token=${server.accessToken}';
  }

  static String mediaUrl(
    PlexServer server,
    PlaybackDecision decision,
    int maxVideoBitrateKbps, {
    required String clientIdentifier,
    required String sessionIdentifier,
    String? sessionId,
    int offsetMs = 0,
  }) {
    return switch (decision) {
      DirectPlay() => directPlayUrl(server, decision.part),
      Transcode() => transcodeUrl(
        server,
        decision,
        maxVideoBitrateKbps,
        clientIdentifier: clientIdentifier,
        sessionIdentifier: sessionIdentifier,
        sessionId: sessionId,
        offsetMs: offsetMs,
      ),
    };
  }
}
