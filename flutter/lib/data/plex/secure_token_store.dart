import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureTokenStore {
  Future<void> saveToken(String token);
  Future<String?> loadToken();
  Future<void> clearToken();
}

const _tokenKey = 'plex_token';

// macOS's default Data Protection Keychain requires a `keychain-access-groups`
// entitlement matched against a real development-signing certificate; ad-hoc
// "Sign to Run Locally" debug builds can't satisfy that and every read/write
// throws PlatformException(-34018). The legacy (non-data-protection) keychain
// this opts into doesn't have that requirement and works fine for a
// single-app token. iOS/Android are unaffected — this option is macOS-only.
const _macOsOptions = MacOsOptions(usesDataProtectionKeychain: false);

/// Ports AndroidTokenStore.kt's role, but not its implementation — that
/// file hand-rolls Android Keystore AES-GCM encryption plus manual IV
/// handling; flutter_secure_storage already does equivalent per-platform
/// key management (Keystore on Android, Keychain on iOS/macOS) internally,
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
}
