import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:reelay/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    // AppRoot eagerly builds AppRootController (via appRootControllerProvider),
    // which constructs a SettingsStore backed by SharedPreferencesAsync —
    // that throws immediately unless a platform is registered, which bare
    // flutter test doesn't do on its own (a real app gets it for free via
    // native plugin registration).
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const ProviderScope(child: ReelayApp()));

    // Splash is showing at this point (AppRoot hasn't resolved a stored
    // token yet) — just confirm the app tree builds without throwing.
    expect(tester.takeException(), isNull);
  });
}
