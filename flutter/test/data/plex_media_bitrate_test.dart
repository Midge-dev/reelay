import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_mappers.dart';
import 'package:reelay/data/plex/plex_models.dart';

void main() {
  test("a Plex file's bitrate (kbps, as Plex gives it), for the quality cap", () {
    final media = PlexMedia.fromJson({'bitrate': 6274, 'videoResolution': '1080', 'Part': []}).toMedia();
    expect(media.bitrateKbps, 6274);
    expect(PlexMedia.fromJson({'Part': []}).toMedia().bitrateKbps, isNull);
  });
}
