import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/app_version.dart';

void main() {
  // CI passes the Play build's name in (see deploy-play-store.yml); a build
  // without it says it's a local one.
  test('the version name comes from APP_VERSION', () {
    const fromCi = String.fromEnvironment('APP_VERSION');
    expect(appVersionName, fromCi.isEmpty ? '0.4-dev' : fromCi);
  });
}
