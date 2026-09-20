import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/plex/plex_identity.dart';
import '../data/plex/secure_token_store.dart';
import '../data/settings/relay_identity_store.dart';
import '../data/settings/settings_store.dart';
import 'app_root_controller.dart';

/// Foundational DI wiring for the Phase 1 data layer — screens read these
/// via ref.watch/ref.read instead of constructing stores themselves.
final sharedPreferencesProvider = Provider<SharedPreferencesAsync>((ref) => SharedPreferencesAsync());

final plexIdentityProvider = Provider<PlexIdentity>((ref) => PlexIdentity(ref.watch(sharedPreferencesProvider)));

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) => FlutterSecureTokenStore());

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  final store = SettingsStore(ref.watch(sharedPreferencesProvider));
  ref.onDispose(store.dispose);
  return store;
});

final relayIdentityStoreProvider = Provider<RelayIdentityStore>((ref) => RelayIdentityStore(ref.watch(sharedPreferencesProvider)));

/// One controller instance for the app's lifetime — mirrors MainActivity.
/// kt's AppRoot composable, whose `remember`ed state/closures live exactly
/// once per process too. `keepAlive` since nothing should ever dispose the
/// app's own root state while it's running.
final appRootControllerProvider = Provider<AppRootController>((ref) {
  final controller = AppRootController(
    tokenStore: ref.watch(secureTokenStoreProvider),
    settingsStore: ref.watch(settingsStoreProvider),
    relayIdentityStore: ref.watch(relayIdentityStoreProvider),
    plexIdentity: ref.watch(plexIdentityProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
