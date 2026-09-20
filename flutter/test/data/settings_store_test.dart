import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('defaults to an empty AppSettings when nothing is stored', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    final settings = await store.observe().first;

    expect(settings.relays, isEmpty);
    expect(settings.maxHostSeats, AppSettings.defaultMaxHostSeats);
    expect(settings.maxVideoBitrateKbps, AppSettings.defaultMaxBitrateKbps);
    store.dispose();
  });

  test('migrates a legacy single relay_url into the relays list exactly once', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
      'relay_url': 'wss://old-relay.example.com',
    });

    final store = SettingsStore(SharedPreferencesAsync());
    final settings = await store.observe().first;

    expect(settings.relays, hasLength(1));
    expect(settings.relays.single.url, 'wss://old-relay.example.com');
    expect(settings.relays.single.isDefault, isTrue);
    expect(settings.defaultRelay?.url, 'wss://old-relay.example.com');

    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('relay_url'), isNull, reason: 'legacy key should be removed after migration');

    store.dispose();
  });

  test('save persists relays and re-emits through observe()', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    await store.observe().first; // wait for initial load

    await store.save(const AppSettings(
      relays: [RelayEntry(id: 'a', nickname: 'Home', url: 'wss://relay.example.com')],
      maxHostSeats: 12,
    ));

    final updated = await store.observe().first;
    expect(updated.relays.single.nickname, 'Home');
    expect(updated.relays.single.isDefault, isTrue, reason: 'save() normalizes a single relay to default');
    expect(updated.maxHostSeats, 12);

    store.dispose();
  });
}
