import '../data/media/media_server_client.dart';

/// Fire-and-forget progress reporting for one playback, on the 5s-interval
/// + on-exit cadence PlayerScreen drives it with. [sessionIdentifier] is
/// the one the stream request carried, so the server ties the reports to
/// the live session.
class TimelineReporter {
  final MediaServerClient client;
  final String sessionIdentifier;

  TimelineReporter(this.client, this.sessionIdentifier);

  Future<void> report(String itemId, PlaybackReportState state, int timeMs, int durationMs) =>
      client.reportProgress(itemId, state, timeMs: timeMs, durationMs: durationMs, sessionIdentifier: sessionIdentifier);
}
