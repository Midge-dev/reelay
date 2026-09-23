import 'package:dio/dio.dart';

import '../data/plex/plex_http_client.dart';
import '../data/plex/plex_models.dart';

/// Plex's timeline (progress) URL — a pure function
/// so it's testable without a live server.
String timelineReportUrl(PlexServer server, String ratingKey, String state, int timeMs, int durationMs) {
  final key = Uri.encodeComponent('/library/metadata/$ratingKey');
  return '${server.baseUrl}/:/timeline'
      '?ratingKey=$ratingKey'
      '&key=$key'
      '&identifier=com.plexapp.plugins.library'
      '&state=$state'
      '&time=$timeMs'
      '&duration=$durationMs';
}

/// Fire-and-forget scrobble reporting to Plex,
/// on the same 5s-interval + on-exit cadence PlayerScreen drives it with.
class TimelineReporter {
  final PlexServer server;
  final String clientIdentifier;

  TimelineReporter(this.server, this.clientIdentifier) : _client = plexHttpClient();

  final Dio _client;

  Future<void> report(String ratingKey, String state, int timeMs, int durationMs) async {
    final url = timelineReportUrl(server, ratingKey, state, timeMs, durationMs);
    try {
      await _client.get<void>(
        url,
        options: Options(headers: {'X-Plex-Token': server.accessToken, 'X-Plex-Client-Identifier': clientIdentifier}),
      );
    } catch (_) {
      // Fire-and-forget: a missed progress report isn't worth surfacing.
    }
  }
}
