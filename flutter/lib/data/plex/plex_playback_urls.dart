import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../media/media_models.dart';
import '../media/media_server.dart';

const _uuid = Uuid();

/// The X-Plex-Platform Reelay reports — Plex keys its transcoder client
/// profiles off this.
String get _plexPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => 'tvOS',
  TargetPlatform.macOS => 'macOS',
  _ => 'Android',
};

String plexDirectPlayUrl(MediaServer server, MediaPart part) =>
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
String plexTranscodeUrl(
  MediaServer server,
  String ratingKey, {
  int? subtitleStreamId,
  required int maxVideoBitrateKbps,
  required String clientIdentifier,
  required String sessionIdentifier,
  String? sessionId,
  int offsetMs = 0,
}) {
  final session = sessionId ?? _uuid.v4();
  final path = Uri.encodeComponent('${server.baseUrl}/library/metadata/$ratingKey');
  final offsetSeconds = offsetMs ~/ 1000;
  return '${server.baseUrl}/video/:/transcode/universal/start.m3u8'
      '?path=$path'
      '&mediaIndex=0&partIndex=0&protocol=hls'
      '&fastSeek=1&copyts=1&offset=$offsetSeconds'
      '&directPlay=0&directStream=0'
      '&videoResolution=1920x1080&maxVideoBitrate=$maxVideoBitrateKbps'
      '&subtitleSize=100'
      '&subtitles=${subtitleStreamId != null ? 'burn' : 'none'}'
      '&subtitleStreamID=${subtitleStreamId ?? 0}'
      '&session=$session'
      '&X-Plex-Product=Reelay'
      '&X-Plex-Platform=$_plexPlatform'
      '&X-Plex-Client-Profile-Name=Generic'
      '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(clientIdentifier)}'
      '&X-Plex-Session-Identifier=${Uri.encodeQueryComponent(sessionIdentifier)}'
      '&X-Plex-Token=${server.accessToken}';
}

/// PUT this before opening a transcode: PMS's transcoder uses whichever
/// audio and subtitle the part has *selected* on the server and ignores the
/// transcode URL's subtitleStreamID (seen against a real PMS — see plezy's
/// `selectSubtitleStreamForBurn`). Plex Web does the same PUT, so it also
/// becomes the remembered choice for next time.
String streamSelectionUrl(MediaServer server, String partId, {int? audioStreamId, int? subtitleStreamId}) =>
    Uri.parse('${server.baseUrl}/library/parts/$partId').replace(
      queryParameters: {
        'audioStreamID': ?audioStreamId?.toString(),
        'subtitleStreamID': ?subtitleStreamId?.toString(),
        'allParts': '1',
      },
    ).toString();

/// Plex's timeline (progress) URL.
String timelineReportUrl(MediaServer server, String ratingKey, String state, int timeMs, int durationMs) {
  final key = Uri.encodeComponent('/library/metadata/$ratingKey');
  return '${server.baseUrl}/:/timeline'
      '?ratingKey=$ratingKey'
      '&key=$key'
      '&identifier=com.plexapp.plugins.library'
      '&state=$state'
      '&time=$timeMs'
      '&duration=$durationMs';
}

/// [sessionIdentifier] is the same `X-Plex-Session-Identifier` the stream
/// request carried ([plexTranscodeUrl]) — it's how PMS ties a report to the
/// live session, so its dashboard shows the real decision (Transcode)
/// instead of a generic Direct Play row.
Map<String, String> timelineReportHeaders(MediaServer server, String clientIdentifier, String sessionIdentifier) => {
  'X-Plex-Token': server.accessToken,
  'X-Plex-Client-Identifier': clientIdentifier,
  'X-Plex-Product': 'Reelay',
  'X-Plex-Session-Identifier': sessionIdentifier,
};
