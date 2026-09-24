import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/settings_store.dart';
import 'package:reelay/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('defaults to an empty AppSettings when nothing is stored', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    final settings = await store.observe().first;

    expect(settings.relays, isEmpty);
    expect(settings.maxHostSeats, AppSettings.defaultMaxHostSeats);
    expect(settings.maxVideoBitrateKbps, AppSettings.defaultMaxBitrateKbps);
    expect(settings.themeId, ThemeId.nocturne);
    expect(settings.uiScale, AppSettings.defaultUiScale);
    store.dispose();
  });

  test('save persists uiScale and re-emits through observe(), surviving a reload', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    await store.observe().first;

    await store.save(const AppSettings(uiScale: 1.3));

    final updated = await store.observe().first;
    expect(updated.uiScale, 1.3);
    store.dispose();

    final reloaded = SettingsStore(SharedPreferencesAsync());
    final reloadedSettings = await reloaded.observe().first;
    expect(reloadedSettings.uiScale, 1.3);
    reloaded.dispose();
  });

  test('Match frame rate starts off and survives a reload once turned on', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    expect((await store.observe().first).matchFrameRate, isFalse);

    await store.save(const AppSettings(matchFrameRate: true));
    store.dispose();

    final reloaded = SettingsStore(SharedPreferencesAsync());
    expect((await reloaded.observe().first).matchFrameRate, isTrue);
    reloaded.dispose();
  });

  test('save persists the theme and re-emits through observe(), surviving a reload', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    await store.observe().first;

    await store.save(const AppSettings(themeId: ThemeId.ember));

    final updated = await store.observe().first;
    expect(updated.themeId, ThemeId.ember);
    store.dispose();

    final reloaded = SettingsStore(SharedPreferencesAsync());
    final reloadedSettings = await reloaded.observe().first;
    expect(reloadedSettings.themeId, ThemeId.ember);
    reloaded.dispose();
  });

  test(
    'migrates a legacy single relay_url into the relays list exactly once',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'relay_url': 'wss://old-relay.example.com',
          });

      final store = SettingsStore(SharedPreferencesAsync());
      final settings = await store.observe().first;

      expect(settings.relays, hasLength(1));
      expect(settings.relays.single.url, 'wss://old-relay.example.com');
      expect(settings.relays.single.isDefault, isTrue);
      expect(settings.defaultRelay?.url, 'wss://old-relay.example.com');

      final prefs = SharedPreferencesAsync();
      expect(
        await prefs.getString('relay_url'),
        isNull,
        reason: 'legacy key should be removed after migration',
      );

      store.dispose();
    },
  );

  test('save persists relays and re-emits through observe()', () async {
    final store = SettingsStore(SharedPreferencesAsync());
    await store.observe().first; // wait for initial load

    await store.save(
      const AppSettings(
        relays: [
          RelayEntry(id: 'a', nickname: 'Home', url: 'wss://relay.example.com'),
        ],
        maxHostSeats: 12,
      ),
    );

    final updated = await store.observe().first;
    expect(updated.relays.single.nickname, 'Home');
    expect(
      updated.relays.single.isDefault,
      isTrue,
      reason: 'save() normalizes a single relay to default',
    );
    expect(updated.maxHostSeats, 12);

    store.dispose();
  });

  test(
    'save persists profiles and re-emits through observe(), surviving a reload',
    () async {
      final store = SettingsStore(SharedPreferencesAsync());
      await store.observe().first;

      const profile = Profile(
        id: 'p1',
        name: 'Sam',
        watchTogetherName: 'Sammy',
        plexUsername: 'GrimLad',
        thumb: 'https://example.com/t.jpg',
      );
      await store.save(const AppSettings(profiles: [profile]));

      final updated = await store.observe().first;
      expect(updated.profiles, hasLength(1));
      expect(updated.profiles.single.name, 'Sam');
      expect(updated.profiles.single.watchTogetherName, 'Sammy');
      expect(updated.profiles.single.plexUsername, 'GrimLad');
      expect(updated.profiles.single.thumb, 'https://example.com/t.jpg');
      store.dispose();

      // A fresh store reading the same backing prefs should see it too.
      final reloaded = SettingsStore(SharedPreferencesAsync());
      final reloadedSettings = await reloaded.observe().first;
      expect(reloadedSettings.profiles.single.id, 'p1');
      reloaded.dispose();
    },
  );
}
