import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/playback/timeline_reporter.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok123');

void main() {
  test('builds the fixed timeline-report query exactly', () {
    final url = timelineReportUrl(_server, '100', 'playing', 5000, 60000);

    expect(
      url,
      'http://192.168.1.5:32400/:/timeline'
      '?ratingKey=100'
      '&key=%2Flibrary%2Fmetadata%2F100'
      '&identifier=com.plexapp.plugins.library'
      '&state=playing'
      '&time=5000'
      '&duration=60000',
    );
  });

  test('report() never throws even if the request fails (fire-and-forget)', () async {
    // No real server at this address — the request will fail; report()
    // must swallow it.
    final reporter = TimelineReporter(const PlexServer(name: 'x', baseUrl: 'http://127.0.0.1:1', accessToken: 't'), 'client-id');
    await expectLater(reporter.report('1', 'playing', 0, 1000), completes);
  });
}
