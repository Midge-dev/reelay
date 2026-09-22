import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/tokens.dart';
import 'app_settings.dart';

const _relayUrlKey = 'relay_url'; // legacy, pre-multi-relay
const _relayEntriesKey = 'relay_entries';
const _maxHostSeatsKey = 'max_host_seats';
const _maxBitrateKey = 'max_video_bitrate_kbps';
const _forceBurnKey = 'force_burn_subtitles';
const _showChatOverlayKey = 'show_chat_overlay';
const _chatOverlayCornerKey = 'chat_overlay_corner';
const _disabledServerIdsKey = 'disabled_server_ids';
const _profilesKey = 'profiles';
const _themeIdKey = 'theme_id';

/// Ports SettingsStore.kt. Kotlin's `ObservableSettings` gives a reactive
/// `Flow` for free because it observes the underlying platform store
/// directly; shared_preferences has no such stream, so this wraps a
/// BehaviorSubject that's seeded on construction and re-pushed on every
/// [save] — valid because this class is the sole writer of these keys
/// anywhere in the app (same assumption Kotlin's `Mutex`-guarded migration
/// makes about being the only writer of the legacy key).
class SettingsStore {
  final SharedPreferencesAsync _prefs;
  final _subject = BehaviorSubject<AppSettings>();
  final _migrationLock = _Mutex();

  SettingsStore(this._prefs) {
    _load();
  }

  Stream<AppSettings> observe() => _subject.stream;

  AppSettings? get current => _subject.valueOrNull;

  Future<void> _load() async {
    final relaysJson = await _prefs.getString(_relayEntriesKey);
    final profilesJson = await _prefs.getString(_profilesKey);
    final settings = AppSettings(
      relays: _decodeRelays(relaysJson),
      maxHostSeats:
          await _prefs.getInt(_maxHostSeatsKey) ??
          AppSettings.defaultMaxHostSeats,
      maxVideoBitrateKbps:
          await _prefs.getInt(_maxBitrateKey) ??
          AppSettings.defaultMaxBitrateKbps,
      forceBurnSubtitles: await _prefs.getBool(_forceBurnKey) ?? false,
      showChatOverlay: await _prefs.getBool(_showChatOverlayKey) ?? true,
      chatOverlayCorner: _decodeCorner(
        await _prefs.getString(_chatOverlayCornerKey),
      ),
      disabledServerIds: _decodeDisabledServerIds(
        await _prefs.getString(_disabledServerIdsKey),
      ),
      profiles: _decodeProfiles(profilesJson),
      themeId: _decodeThemeId(await _prefs.getString(_themeIdKey)),
    );
    _subject.add(await _migrateLegacyRelayUrlIfNeeded(settings));
  }

  List<RelayEntry> _decodeRelays(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => RelayEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<Profile> _decodeProfiles(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Set<String> _decodeDisabledServerIds(String? json) {
    if (json == null || json.trim().isEmpty) return const {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return const {};
    }
  }

  ChatOverlayCorner _decodeCorner(String? name) {
    for (final corner in ChatOverlayCorner.values) {
      if (corner.name == name) return corner;
    }
    return ChatOverlayCorner.bottomEnd;
  }

  ThemeId _decodeThemeId(String? name) {
    for (final id in ThemeId.values) {
      if (id.name == name) return id;
    }
    return ThemeId.nocturne;
  }

  Future<AppSettings> _migrateLegacyRelayUrlIfNeeded(AppSettings current) =>
      _migrationLock.run(() async {
        if (current.relays.isNotEmpty) return current;
        if (await _prefs.getString(_relayEntriesKey) != null) return current;
        final legacyUrl = await _prefs.getString(_relayUrlKey);
        if (legacyUrl == null || legacyUrl.isEmpty) return current;

        final migrated = current.copyWith(
          relays: [
            RelayEntry(
              id: _randomRelayId(),
              nickname: 'My relay',
              url: legacyUrl,
              isDefault: true,
            ),
          ],
        );
        await save(migrated);
        await _prefs.remove(_relayUrlKey);
        return migrated;
      });

  Future<void> save(AppSettings appSettings) async {
    final defaultId =
        appSettings.relays.where((r) => r.isDefault).firstOrNull?.id ??
        appSettings.relays.firstOrNull?.id;
    final normalizedRelays = appSettings.relays
        .map((r) => r.copyWith(isDefault: r.id == defaultId))
        .toList();
    final normalized = appSettings.copyWith(relays: normalizedRelays);

    if (normalizedRelays.isNotEmpty) {
      await _prefs.setString(
        _relayEntriesKey,
        jsonEncode(normalizedRelays.map((r) => r.toJson()).toList()),
      );
    } else {
      await _prefs.remove(_relayEntriesKey);
    }
    await _prefs.setInt(_maxHostSeatsKey, normalized.maxHostSeats);
    await _prefs.setInt(_maxBitrateKey, normalized.maxVideoBitrateKbps);
    await _prefs.setBool(_forceBurnKey, normalized.forceBurnSubtitles);
    await _prefs.setBool(_showChatOverlayKey, normalized.showChatOverlay);
    await _prefs.setString(
      _chatOverlayCornerKey,
      normalized.chatOverlayCorner.name,
    );
    if (normalized.disabledServerIds.isNotEmpty) {
      await _prefs.setString(
        _disabledServerIdsKey,
        jsonEncode(normalized.disabledServerIds.toList()),
      );
    } else {
      await _prefs.remove(_disabledServerIdsKey);
    }
    if (normalized.profiles.isNotEmpty) {
      await _prefs.setString(
        _profilesKey,
        jsonEncode(normalized.profiles.map((p) => p.toJson()).toList()),
      );
    } else {
      await _prefs.remove(_profilesKey);
    }
    await _prefs.setString(_themeIdKey, normalized.themeId.name);

    _subject.add(normalized);
  }

  void dispose() => _subject.close();
}

String _randomRelayId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz';
  final random = Random.secure();
  return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Minimal async mutex (ports Kotlin's `Mutex`/`withLock`) — chains callers
/// onto the previous holder's completion rather than pulling in a whole
/// package for one lock.
class _Mutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }
}
