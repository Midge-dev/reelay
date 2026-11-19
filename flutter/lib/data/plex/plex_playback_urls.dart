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

/// What a transcode should come out as, told to PMS alongside the `Generic`
/// client profile — which names no transcode targets of its own, so without
/// this PMS refuses every transcode with a 400 (decision code 4005).
/// HLS in MPEG-TS with H.264 is what the Shield's player takes most
/// reliably. It's a query string in its own right, so its commas stay
/// encoded inside it and the whole thing is encoded again as one value.
const plexTranscodeProfileExtra =
    'add-transcode-target(type=videoProfile&context=streaming'
    '&protocol=hls&container=mpegts&videoCodec=h264'
    '&audioCodec=aac%2Cac3%2Ceac3)';

String plexDirectPlayUrl(MediaServer server, MediaPart part) =>
    '${server.baseUrl}${part.key}?X-Plex-Token=${server.accessToken}';

// offsetMs tells Plex where in the source to *start encoding*. The player
// still reports the film's own time (copyts=1 keeps the source timestamps:
// checked on the Shield 2026-11-18 — a transcode resumed at 30 min shows
// 30:00 of the full running time), so positions need no offset added. A
// client-side seekTo() after opening this URL is not just redundant but
// actively wrong: it asks for a position Plex's transcode session was never
// told about and hasn't produced segments for, which 400s (see project
// notes on the CC-cycle-mid-playback crash this fixed).
//
// The X-Plex-* identity params are required: with no platform or profile
// name, PMS logs "Unable to find client profile for device" and 400s the
// request. `Generic` is PMS's built-in profile for a plain HLS client, and
// it needs [plexTranscodeProfileExtra] to know what to transcode into.
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
      // Which track burns comes from the part's server-side selection (see
      // streamSelectionUrl), never from here: PMS ignores a subtitleStreamID
      // on this endpoint and burns the selected one (plezy measured it).
      '&subtitles=${subtitleStreamId != null ? 'burn' : 'none'}'
      '&session=$session'
      '&X-Plex-Product=Reelay'
      '&X-Plex-Platform=$_plexPlatform'
      '&X-Plex-Client-Profile-Name=Generic'
      '&X-Plex-Client-Profile-Extra=${Uri.encodeComponent(plexTranscodeProfileExtra)}'
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

/// The transcoder's own verdict on [transcodeStartUrl] — the same request,
/// asked of `/decision` instead of `start.m3u8`. Plex's apps ask first; it
/// answers in words when it won't, where the stream itself just 400s.
String plexTranscodeDecisionUrl(String transcodeStartUrl) =>
    transcodeStartUrl.replaceFirst('/video/:/transcode/universal/start.m3u8', '/video/:/transcode/universal/decision');

/// Ends the transcode for [session] on the server, so it isn't left running
/// once nothing is watching it.
String plexStopTranscodeUrl(MediaServer server, String session, String clientIdentifier) =>
    '${server.baseUrl}/video/:/transcode/universal/stop'
    '?session=${Uri.encodeQueryComponent(session)}'
    '&X-Plex-Client-Identifier=${Uri.encodeQueryComponent(clientIdentifier)}'
    '&X-Plex-Token=${server.accessToken}';

/// Why a `/decision` answer refuses, in Plex's own words; null when it'll
/// stream. Codes of 2000 and up are refusals (1000 direct play, 1001
/// transcode); the first failing one's text is the reason.
String? plexTranscodeRefusal(Object? body) {
  final container = body is Map ? body['MediaContainer'] : null;
  if (container is! Map) return null;
  for (final kind in const ['general', 'transcode', 'mde', 'directPlay']) {
    final code = int.tryParse('${container['${kind}DecisionCode']}');
    if (code != null && code >= 2000) {
      final text = container['${kind}DecisionText'];
      return text is String && text.trim().isNotEmpty ? text.trim() : 'refused with code $code';
    }
  }
  return null;
}
