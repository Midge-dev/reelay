import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/jellyfin/jellyfin_auth_api.dart';
import 'package:reelay/data/media/media_server.dart';
import 'package:reelay/data/plex/plex_identity.dart';
import 'package:reelay/data/plex/secure_token_store.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/relay_identity_store.dart';
import 'package:reelay/data/settings/settings_store.dart';
import 'package:reelay/state/app_root_controller.dart';
import 'package:reelay/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MemoryTokenStore implements SecureTokenStore {
  final values = <String, String>{};

  @override
  Future<void> saveToken(String token) async => values['plex'] = token;
  @override
  Future<String?> loadToken() async => values['plex'];
  @override
  Future<void> clearToken() async => values.remove('plex');
  @override
  Future<void> saveTokenForProfile(String profileId, String token) async => values['plex:$profileId'] = token;
  @override
  Future<String?> loadTokenForProfile(String profileId) async => values['plex:$profileId'];
  @override
  Future<void> clearTokenForProfile(String profileId) async => values.remove('plex:$profileId');
  @override
  Future<void> saveJellyfinToken(String profileId, String token) async => values['jellyfin:$profileId'] = token;
  @override
  Future<String?> loadJellyfinToken(String profileId) async => values['jellyfin:$profileId'];
  @override
  Future<void> clearJellyfinToken(String profileId) async => values.remove('jellyfin:$profileId');
}

const _sam = Profile(id: 'p1', name: 'Sam', watchTogetherName: 'Sammy', plexUsername: 'GrimLad');
const _maya = Profile(id: 'p2', name: 'Maya', watchTogetherName: 'Maya', plexUsername: 'maya');

// Nothing listens here, so the best-effort sign-out fails fast and quietly.
const _server = JellyfinServerInfo(baseUrl: 'http://127.0.0.1:9', id: 'server-1', name: 'Loft', version: '12.1.0');
const _session = JellyfinSession(accessToken: 'token-1', userId: 'user-1', userName: 'sam', serverId: 'server-1');

void main() {
  group('a profile\'s Jellyfin link', () {
    test('round-trips through JSON', () {
      final linked = _sam.withJellyfin(
        const JellyfinLink(
          serverId: 'server-1',
          serverName: 'Loft',
          baseUrl: 'http://loft:8096',
          userId: 'user-1',
          username: 'sam',
        ),
      );
      final back = Profile.fromJson(linked.toJson());
      expect(back.jellyfin?.serverId, 'server-1');
      expect(back.jellyfin?.serverName, 'Loft');
      expect(back.jellyfin?.baseUrl, 'http://loft:8096');
      expect(back.jellyfin?.userId, 'user-1');
      expect(back.jellyfin?.username, 'sam');
      expect(back.plexUsername, 'GrimLad');
    });

    test('a profile saved before Jellyfin existed loads with none', () {
      final old = Profile.fromJson({
        'id': 'p1',
        'name': 'Sam',
        'watchTogetherName': 'Sammy',
        'plexUsername': 'GrimLad',
        'thumb': null,
      });
      expect(old.jellyfin, isNull);
      expect(old.toJson().containsKey('jellyfin'), isFalse);
    });

    test('a link from before device ids loads with none, and uses the install\'s', () {
      final old = JellyfinLink.fromJson({
        'serverId': 'server-1',
        'serverName': 'Loft',
        'baseUrl': 'http://loft:8096',
        'userId': 'user-1',
        'username': 'sam',
      });
      expect(old.deviceId, isNull);
      expect(old.toJson().containsKey('deviceId'), isFalse);
    });
  });

  group('linking Jellyfin to a profile', () {
    late _MemoryTokenStore tokens;
    late SettingsStore settings;
    late AppRootController controller;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      tokens = _MemoryTokenStore();
      settings = SettingsStore(prefs);
      await settings.save(const AppSettings(profiles: [_sam, _maya]));
      controller = AppRootController(
        tokenStore: tokens,
        settingsStore: settings,
        relayIdentityStore: RelayIdentityStore(prefs),
        plexIdentity: PlexIdentity(prefs),
      );
    });

    tearDown(() => settings.dispose());

    test('saves the link on the profile and the token in secure storage', () async {
      final linked = await controller.linkJellyfin(_sam, _server, _session);

      expect(linked.jellyfin?.serverId, 'server-1');
      expect(linked.jellyfin?.username, 'sam');
      expect(linked.toJson().toString(), isNot(contains('token-1')), reason: 'the token never goes in settings');
      expect(tokens.values['jellyfin:p1'], 'token-1');
      expect(tokens.values.containsKey('plex:p1'), isFalse, reason: 'the Plex token is untouched');

      final saved = (await settings.observe().first).profiles;
      expect(saved.firstWhere((p) => p.id == 'p1').jellyfin?.userId, 'user-1');
      expect(saved.firstWhere((p) => p.id == 'p2').jellyfin, isNull, reason: 'other profiles keep their own');
      expect(saved.map((p) => p.id), ['p1', 'p2'], reason: 'order kept');
    });

    test("becomes the profile's Jellyfin server", () async {
      final linked = await controller.linkJellyfin(_sam, _server, _session);
      final server = await controller.jellyfinServerFor(linked);

      expect(server?.backend, MediaBackend.jellyfin);
      expect(server?.name, 'Loft');
      expect(server?.baseUrl, 'http://127.0.0.1:9');
      expect(server?.accessToken, 'token-1');
      expect(server?.id, 'server-1');
      expect(server?.userId, 'user-1');
    });

    test('each link keeps the device id it signed in as, and the server presents it', () async {
      const samSession = JellyfinSession(
        accessToken: 'token-1',
        userId: 'user-1',
        userName: 'sam',
        serverId: 'server-1',
        deviceId: 'device-sam',
      );
      const mayaSession = JellyfinSession(
        accessToken: 'token-2',
        userId: 'user-1',
        userName: 'sam',
        serverId: 'server-1',
        deviceId: 'device-maya',
      );
      final sam = await controller.linkJellyfin(_sam, _server, samSession);
      final maya = await controller.linkJellyfin(_maya, _server, mayaSession);

      // Saved, so it survives a restart.
      final saved = (await settings.observe().first).profiles;
      expect(saved.firstWhere((p) => p.id == 'p1').jellyfin?.deviceId, 'device-sam');
      expect(Profile.fromJson(sam.toJson()).jellyfin?.deviceId, 'device-sam');
      // Two profiles, even as the same Jellyfin user, never share one — a
      // second sign-in from the same id would revoke the first's token.
      expect((await controller.jellyfinServerFor(sam))?.clientId, 'device-sam');
      expect((await controller.jellyfinServerFor(maya))?.clientId, 'device-maya');
    });

    test('no link, or a lost token, is no Jellyfin server', () async {
      expect(await controller.jellyfinServerFor(_sam), isNull);

      final linked = await controller.linkJellyfin(_sam, _server, _session);
      tokens.values.remove('jellyfin:p1');
      expect(await controller.jellyfinServerFor(linked), isNull);
    });

    test('linking again replaces the account', () async {
      final first = await controller.linkJellyfin(_sam, _server, _session);
      const other = JellyfinSession(accessToken: 'token-2', userId: 'user-2', userName: 'sam2', serverId: 'server-1');
      final second = await controller.linkJellyfin(first, _server, other);

      expect(second.jellyfin?.userId, 'user-2');
      expect(tokens.values['jellyfin:p1'], 'token-2');
    });

    test('unlinking forgets the link and the token', () async {
      final linked = await controller.linkJellyfin(_sam, _server, _session);
      final unlinked = await controller.unlinkJellyfin(linked);

      expect(unlinked.jellyfin, isNull);
      expect(tokens.values.containsKey('jellyfin:p1'), isFalse);
      final saved = (await settings.observe().first).profiles.firstWhere((p) => p.id == 'p1');
      expect(saved.jellyfin, isNull);
    });
  });

  group('a Jellyfin-only setup', () {
    late _MemoryTokenStore tokens;
    late SettingsStore settings;
    late AppRootController controller;

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      tokens = _MemoryTokenStore();
      settings = SettingsStore(prefs);
      await settings.observe().first;
      controller = AppRootController(
        tokenStore: tokens,
        settingsStore: settings,
        relayIdentityStore: RelayIdentityStore(prefs),
        plexIdentity: PlexIdentity(prefs),
      );
    });

    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    test('makes a profile named for the Jellyfin user, with no Plex account', () async {
      await controller.completeSetup(jellyfin: (_server, _session));

      final profile = (await settings.observe().first).profiles.single;
      expect(profile.name, 'sam');
      expect(profile.plexUsername, isNull);
      expect(profile.jellyfin?.serverName, 'Loft');
      expect(profile.accountsLabel, 'Jellyfin · sam');
      expect(tokens.values['jellyfin:${profile.id}'], 'token-1');
      expect(tokens.values.keys.where((k) => k.startsWith('plex')), isEmpty);
      expect(controller.activeProfile?.id, profile.id);
    });

    // _server's address has nothing listening, so these reach screen 24.
    test('connects to its Jellyfin server alone — no Plex sign-in needed', () async {
      await controller.completeSetup(jellyfin: (_server, _session));
      final state = controller.state;
      expect(state, isA<NoServersReachable>());
      state as NoServersReachable;
      expect(state.token, isNull);
      expect(state.resources, isEmpty);
      expect(state.jellyfin?.serverName, 'Loft');
      expect(controller.accountToken, isNull);
    });

    test('does the same at the next launch', () async {
      await controller.completeSetup(jellyfin: (_server, _session));
      final profile = (await settings.observe().first).profiles.single;
      await controller.selectProfile(profile);
      expect(controller.state, isA<NoServersReachable>());
      expect((controller.state as NoServersReachable).jellyfin?.serverName, 'Loft');
    });
  });
}
