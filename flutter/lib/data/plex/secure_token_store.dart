import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureTokenStore {
  Future<void> saveToken(String token);
  Future<String?> loadToken();
  Future<void> clearToken();

  /// Per-profile variants — screen 07's picker binds one Plex account
  /// token per [Profile], distinct from the single legacy key above
  /// (which stays around only to migrate a pre-profiles install's one
  /// signed-in account into that profile's own keyed token).
  Future<void> saveTokenForProfile(String profileId, String token);
  Future<String?> loadTokenForProfile(String profileId);
  Future<void> clearTokenForProfile(String profileId);
}

const _tokenKey = 'plex_token';
String _profileTokenKey(String profileId) => 'plex_token_$profileId';

// macOS's default Data Protection Keychain requires a `keychain-access-groups`
// entitlement matched against a real development-signing certificate; ad-hoc
// "Sign to Run Locally" debug builds can't satisfy that and every read/write
// throws PlatformException(-34018). The legacy (non-data-protection) keychain
// this opts into doesn't have that requirement and works fine for a
// single-app token. iOS/Android are unaffected — this option is macOS-only.
const _macOsOptions = MacOsOptions(usesDataProtectionKeychain: false);

/// Plex tokens in platform secure storage: flutter_secure_storage does the
/// per-platform key management (Keystore on Android, Keychain on iOS/macOS),
/// so none of that crypto needs porting.
class FlutterSecureTokenStore implements SecureTokenStore {
  final FlutterSecureStorage _storage;

  FlutterSecureTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token, mOptions: _macOsOptions);

  @override
  Future<String?> loadToken() => _storage.read(key: _tokenKey, mOptions: _macOsOptions);

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey, mOptions: _macOsOptions);

  @override
  Future<void> saveTokenForProfile(String profileId, String token) =>
      _storage.write(key: _profileTokenKey(profileId), value: token, mOptions: _macOsOptions);

  @override
  Future<String?> loadTokenForProfile(String profileId) =>
      _storage.read(key: _profileTokenKey(profileId), mOptions: _macOsOptions);

  @override
  Future<void> clearTokenForProfile(String profileId) =>
      _storage.delete(key: _profileTokenKey(profileId), mOptions: _macOsOptions);
}
