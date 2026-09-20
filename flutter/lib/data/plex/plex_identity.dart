import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _clientIdentifierKey = 'client_identifier';

class PlexIdentity {
  final SharedPreferencesAsync _prefs;
  final Uuid _uuid = const Uuid();

  PlexIdentity(this._prefs);

  Future<String> getOrCreateClientIdentifier() async {
    final existing = await _prefs.getString(_clientIdentifierKey);
    if (existing != null) return existing;

    final generated = _uuid.v4();
    await _prefs.setString(_clientIdentifierKey, generated);
    return generated;
  }
}
