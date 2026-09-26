import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/plex/plex_auth_api.dart';
import '../data/plex/plex_http_client.dart';
import '../data/plex/plex_identity.dart';
import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart';
import '../data/plex/plex_server_api.dart';
import '../data/plex/plex_watchlist_api.dart';
import '../data/plex/secure_token_store.dart';
import '../data/settings/app_settings.dart';
import '../data/settings/relay_identity_store.dart';
import '../data/settings/settings_store.dart';
import '../focus/screen_memory.dart';
import '../screens/home/watch_together_row.dart';
import '../sync/relay_client.dart';
import '../sync/relay_directory_api.dart';
import '../sync/relay_protocol.dart';
import 'app_state.dart';
import 'duplicate_fold.dart';

const _sectionTypeShow = 'show';
const _roomPollIntervalMs = 5000;
const _joinRoomTimeoutMs = 5000;

class _FriendlyError implements Exception {
  final String message;
  const _FriendlyError(this.message);
  @override
  String toString() => message;
}

/// The app's state and everything that changes it. One ChangeNotifier:
/// state, account, watchlist and live rooms are one reactive surface, not
/// split across several Riverpod providers, since several screens (MovieDetail/EpisodeDetail's
/// watchlist star, Home's WatchTogetherRow, Lobby/Player's relay) all need
/// pieces of it independently of which AppState is current.
class AppRootController extends ChangeNotifier {
  AppRootController({
    required this._tokenStore,
    required this._settingsStore,
    required this._relayIdentityStore,
    required this._plexIdentity,
  });

  final SecureTokenStore _tokenStore;
  final SettingsStore _settingsStore;
  final RelayIdentityStore _relayIdentityStore;
  final PlexIdentity _plexIdentity;
  final _relayDirectoryApi = RelayDirectoryApi();

  AppState _state = const Checking();
  AppState get state => _state;

  void _setState(AppState next) {
    final wasPolling = pollsLiveRooms(_state);
    final polls = pollsLiveRooms(next);
    _state = next;
    if (polls && !wasPolling) {
      _startRoomPolling();
    } else if (!polls && wasPolling) {
      _stopRoomPolling();
    }
    notifyListeners();
  }

  String _clientIdentifier = '';
  String get clientIdentifier => _clientIdentifier;

  PlexAccount? _localAccount;
  PlexAccount? get localAccount => _localAccount;

  String? _accountToken;
  String? get accountToken => _accountToken;
  String get accountTokenOrEmpty => _accountToken ?? '';

  Profile? _activeProfile;
  Profile? get activeProfile => _activeProfile;

  AppSettings get currentSettings =>
      _settingsStore.current ?? const AppSettings();

  Future<void> saveBitratePreference(int kbps) {
    final updated = currentSettings.copyWith(maxVideoBitrateKbps: kbps);
    return _settingsStore.save(updated);
  }

  List<PlexWatchlistItem>? _watchlistItems;
  List<PlexWatchlistItem> get watchlist => _watchlistItems ?? const [];

  // ratingKey -> the name of a connected server holding that watchlist
  // title, or null when none does. A key that's absent hasn't been looked
  // up yet.
  Map<String, String?> _watchlistAvailability = {};
  Map<String, String?> get watchlistAvailability => _watchlistAvailability;

  // Multi-server hub: every reachable, non-disabled server the account can
  // see, probed concurrently at connect time — see
  // PlexResourcesApi.connectToAllServers. Home/Library content is now
  // fanned out across all of these and merged (see _loadHome/_fetchGroupItems
  // below); duplicate folding across them lands in the next phase.
  List<ReachableServer> _connectedServers = const [];
  List<ReachableServer> get connectedServers => _connectedServers;
  List<PlexResource> _unreachableResources = const [];
  List<PlexResource> get unreachableResources => _unreachableResources;

  RelayIdentity? _relayIdentity;
  RelayClient? _relayClient;
  RelayClient? get relayClient => _relayClient;

  Map<String, List<RelayRoomSummary>> _liveRoomsByRelay = {};
  Map<String, RelayEntry> _liveRelaysById = {};
  Set<String> _hostedRoomIds = {};
  Set<String> get hostedRoomIds => _hostedRoomIds;

  Timer? _roomPollTimer;
  final _pollInFlight = <String>{};

  StreamSubscription<String?>? _myRoomIdSub;
  String? _myRoomId;
  String? get myRoomId => _myRoomId;

  Map<String, RelayHealth> _relayHealth = {};

  /// Every configured relay (deduped by URL, same as polling), in settings
  /// order — the rooms panel lists an unreachable relay's group even though
  /// it contributes no rooms.
  List<RelayEntry> get liveRelays => _liveRelaysById.values.toList();

  /// Last poll result per relay id; absent until the first answer (or
  /// failure) comes back.
  Map<String, RelayHealth> get relayHealth => _relayHealth;

  /// "Retry now" on screen 12 — hurries the next poll rather than waiting
  /// for the timer.
  void retryRelays() => unawaited(_pollRooms());

  List<MergedRoom> get liveRooms => [
    for (final entry in _liveRoomsByRelay.entries)
      if (_liveRelaysById[entry.key] != null)
        for (final room in entry.value)
          MergedRoom(_liveRelaysById[entry.key]!, room),
  ];

  @override
  void dispose() {
    _roomPollTimer?.cancel();
    _myRoomIdSub?.cancel();
    _relayClient?.dispose();
    super.dispose();
  }

  // ---- Startup / auth ----

  Future<void> start() async {
    final settings = await _settingsStore.observe().first;
    final profiles = settings.profiles;

    if (profiles.isEmpty) {
      // Pre-profiles install: migrate whatever single account was already
      // signed in into profile #1 (DESIGN.md's "the first profile is
      // everybody" — a picker never even existed before this).
      final legacyToken = await _tokenStore.loadToken();
      if (legacyToken != null) {
        await completeFirstLogin(legacyToken);
      } else {
        _setState(const LoggedOut());
      }
      return;
    }

    if (profiles.length == 1) {
      // Never shown the picker for a single-person household.
      await selectProfile(profiles.first);
      return;
    }

    _setState(ProfilePicker(profiles: profiles));
  }

  /// Fetches the account, wraps it in a [Profile], persists it, and saves
  /// its own keyed token — but does not activate it. Callers decide
  /// whether creating a profile also means becoming it (the picker/first
  /// login do; provisioning one for someone else from Settings doesn't).
  Future<Profile> _createProfile({
    required String token,
    required String? name,
    required String? watchTogetherName,
  }) async {
    final clientId = await _plexIdentity.getOrCreateClientIdentifier();
    PlexAccount? account;
    try {
      account = await PlexAuthApi(clientId).fetchAccount(token);
    } catch (_) {
      account = null;
    }
    final resolvedName = name ?? account?.username ?? 'You';
    final profile = Profile(
      id: _randomProfileId(),
      name: resolvedName,
      watchTogetherName: (watchTogetherName?.isNotEmpty ?? false)
          ? watchTogetherName!
          : resolvedName,
      plexUsername: account?.username ?? resolvedName,
      thumb: account?.thumb,
    );

    await _tokenStore.saveTokenForProfile(profile.id, token);
    final settings = await _settingsStore.observe().first;
    await _settingsStore.save(
      settings.copyWith(profiles: [...settings.profiles, profile]),
    );
    return profile;
  }

  /// Settings' "add a profile" — provisions one for someone else to pick
  /// later without switching away from whoever is currently signed in.
  Future<Profile> addProfile({
    required String name,
    required String watchTogetherName,
    required String token,
  }) => _createProfile(
    token: token,
    name: name,
    watchTogetherName: watchTogetherName,
  );

  /// Screen 07b via the picker — creating a profile there means becoming
  /// it immediately, reusing the same PIN-link flow first-run login uses.
  Future<void> addProfileAndActivate({
    required String name,
    required String watchTogetherName,
    required String token,
  }) async {
    final profile = await _createProfile(
      token: token,
      name: name,
      watchTogetherName: watchTogetherName,
    );
    _activeProfile = profile;
    await connect(token);
  }

  /// OnboardingScreen's onComplete, for the case start() found no profiles and
  /// no legacy token — creates profile #1 from whatever account just
  /// signed in and activates it (there's no one else to fall back to),
  /// same as the migration path in start() does for a pre-profiles install.
  Future<void> completeFirstLogin(String token) async {
    final profile = await _createProfile(
      token: token,
      name: null,
      watchTogetherName: null,
    );
    _activeProfile = profile;
    await connect(token, firstRun: true);
  }

  static const _numberWords = [
    'No',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
  ];

  /// "Two servers", "One library" — O5's headline reads as a sentence.
  static String _countWord(int n, String singular, {String? plural}) {
    final word = n < _numberWords.length ? _numberWords[n] : '$n';
    return '$word ${n == 1 ? singular : (plural ?? '${singular}s')}';
  }

  Future<void> selectProfile(Profile profile) async {
    final token = await _tokenStore.loadTokenForProfile(profile.id);
    if (token == null) {
      // The keyed token is gone (cleared externally, etc.) — nothing to
      // recover automatically; back to sign-in is the only honest option.
      _setState(const LoggedOut());
      return;
    }
    _activeProfile = profile;
    await connect(token);
  }

  Future<void> connect(String token, {bool firstRun = false}) async {
    _accountToken = token;
    _clientIdentifier = await _plexIdentity.getOrCreateClientIdentifier();
    // Start probing servers now, alongside the account fetch — the probe
    // doesn't need the account, and doing them one after the other added
    // the account round trip to every cold start. Errors are carried to
    // the await below rather than escaping unhandled meanwhile.
    final settings = await _settingsStore.observe().first;
    final resourcesApi = PlexResourcesApi(_clientIdentifier);
    final probing = resourcesApi
        .connectToAllServers(
          token,
          disabledMachineIdentifiers: settings.disabledServerIds,
        )
        .then<(ConnectedServers?, Object?)>(
          (v) => (v, null),
          onError: (Object e) => (null, e),
        );
    final authApi = PlexAuthApi(_clientIdentifier);
    try {
      _localAccount = await authApi.fetchAccount(token);
    } catch (_) {
      _localAccount = null;
    }
    final username = _localAccount?.username;
    final done = <String>[
      if (username != null)
        'Signed in to Plex as $username'
      else
        'Signed in to Plex',
    ];
    void progress(String? current, {String? headline}) => _setState(
      ConnectingToServer(
        username: username,
        firstRun: firstRun,
        done: List.of(done),
        current: current,
        headline: headline,
      ),
    );
    progress('Looking for your servers');

    try {
      final (probedOrNull, probeError) = await probing;
      if (probeError != null) throw probeError;
      final probed = probedOrNull!;
      final reached = probed.connected.length;
      done.add(
        'Reached $reached server${reached == 1 ? '' : 's'}${probed.unreachable.isEmpty ? '' : ' · ${probed.unreachable.length} not answering'}',
      );
      progress('Reading libraries');
      _connectedServers = probed.connected;
      _unreachableResources = probed.unreachable;
      if (probed.connected.isEmpty) {
        // Screen 24 — this is the one failure that earns the whole screen,
        // so it gets a real state (with the account's resource list, for a
        // named-per-server display) rather than falling into the generic
        // AppError catch below, which would just print the raw exception.
        // A deliberately-empty hub (every server disabled) reaches this
        // same screen for now — see the plan's open question on distinct
        // messaging for that case.
        List<PlexResource> resources;
        try {
          resources = await resourcesApi.listServers(token);
        } catch (_) {
          resources = const [];
        }
        _setState(NoServersReachable(token: token, resources: resources));
        unawaited(_refreshWatchlist());
        return;
      }
      final sectionsByServerId = await _fetchAllSections(probed.connected);
      final sectionGroups = groupSections(sectionsByServerId);
      final firstGroup = sectionGroups.firstOrNull;
      if (firstGroup == null) {
        throw _FriendlyError(
          'No movie or show library found on any connected server',
        );
      }
      final libraries = sectionGroups.length;
      done.add(
        'Found $libraries librar${libraries == 1 ? 'y' : 'ies'} across $reached server${reached == 1 ? '' : 's'}',
      );
      progress(
        'Loading your home screen',
        headline:
            '${_countWord(reached, 'server')}, ${_countWord(libraries, 'library', plural: 'libraries')}',
      );
      // Home is built from on-deck/recent/suggestion hubs alone — a
      // library's full title list is fetched when that library is opened,
      // never at startup (it held the splash for seconds on a large one).
      final ctx = LibraryContext(
        servers: probed.connected,
        sectionGroups: sectionGroups,
        selectedSectionGroup: firstGroup,
        items: const [],
      );
      // The Watch Together step is offered once: skipping it during setup
      // ("Not now") is an answer, not something to ask again every launch.
      final offerRelayStep = settings.relays.isEmpty && !settings.setupComplete;
      _setState(
        offerRelayStep
            ? RelaySetup(ctx: ctx)
            : await _loadHome(probed.connected, sectionGroups),
      );
    } catch (e) {
      if (isPlexSignInRevoked(e)) {
        await _forgetRevokedSignIn();
        return;
      }
      // Name what failed, never the raw exception.
      _setState(
        AppError(
          message: e is _FriendlyError ? e.message : "Plex didn't answer. Check this TV's connection, then try again.",
          retryState: const LoggedOut(),
        ),
      );
      return;
    }
    unawaited(_refreshWatchlist());
  }

  /// Plex refused the saved token (this TV was removed from the account's
  /// devices). Drop it and go back to linking, for the same profile.
  Future<void> _forgetRevokedSignIn() async {
    final profile = _activeProfile;
    if (profile != null) await _tokenStore.clearTokenForProfile(profile.id);
    await _tokenStore.clearToken();
    _accountToken = null;
    _setState(LoggedOut(relinkProfile: profile));
  }

  /// Linking again after [_forgetRevokedSignIn]: the new token goes back
  /// on the profile it came from — its settings, relays and choices intact.
  Future<void> relink(Profile profile, String token) async {
    await _tokenStore.saveTokenForProfile(profile.id, token);
    _activeProfile = profile;
    await connect(token);
  }

  /// Toggles one server in or out of the hub (screen 06's switcher panel —
  /// there's no more "the active server" to switch to, every non-disabled
  /// reachable server contributes at once) and runs the same reconnect
  /// [connect] already does on startup — there's no lighter in-place swap;
  /// every AppState variant carries its own server copy (see
  /// app_state.dart), so a full reconnect is what actually replaces all of
  /// them consistently.
  Future<void> setServerEnabled(String machineIdentifier, bool enabled) async {
    final settings = await _settingsStore.observe().first;
    final disabled = {...settings.disabledServerIds};
    if (enabled) {
      disabled.remove(machineIdentifier);
    } else {
      disabled.add(machineIdentifier);
    }
    await _settingsStore.save(settings.copyWith(disabledServerIds: disabled));
    final token = _accountToken;
    if (token != null) await connect(token);
  }

  // ---- Multi-server fan-out helpers ----

  /// Fetches every connected server's sections concurrently, tolerant of
  /// per-server failure (a server that stops answering mid-fetch simply
  /// contributes no sections, same as any other per-call `.catchError` in
  /// this file — it doesn't fail the other servers' results).
  Future<Map<String, List<PlexSection>>> _fetchAllSections(
    List<ReachableServer> servers,
  ) async {
    final results = await Future.wait(
      servers.map((cs) async {
        List<PlexSection> sections;
        try {
          sections = await PlexServerApi(
            cs.server,
            _clientIdentifier,
          ).fetchSections();
        } catch (_) {
          sections = const [];
        }
        return MapEntry(cs.server.machineIdentifier, sections);
      }),
    );
    return Map.fromEntries(results);
  }

  /// Fetches a [SectionGroup]'s items from every server that has a matching
  /// physical section, fanned out concurrently and merged — not yet folded
  /// into one card per work, just tagged with which server each copy came
  /// from (see [Sourced]).
  Future<List<Sourced<PlexLibraryItem>>> _fetchGroupItems(
    List<ReachableServer> servers,
    SectionGroup group,
  ) async {
    final results = await Future.wait(
      servers.map((cs) async {
        final section = group.sectionOn(cs.server.machineIdentifier);
        if (section == null) return const <Sourced<PlexLibraryItem>>[];
        try {
          final items = await PlexServerApi(
            cs.server,
            _clientIdentifier,
          ).fetchLibraryItems(section.key);
          return items
              .map((i) => Sourced(i, cs.server, cs.reachability))
              .toList();
        } catch (_) {
          return const <Sourced<PlexLibraryItem>>[];
        }
      }),
    );
    return results.expand((l) => l).toList();
  }

  /// Looks a ratingKey up on every connected server until one answers —
  /// used where a piece of content is known only by its ratingKey with no
  /// server hint at all (a Watch Together room only carries a ratingKey,
  /// not which server hosted it).
  Future<(PlexServer, PlexMovieDetail)?> _fetchMovieDetailFromAnyServer(
    List<ReachableServer> servers,
    String ratingKey,
  ) async {
    final results = await Future.wait(
      servers.map((cs) async {
        try {
          return (
            cs.server,
            await PlexServerApi(
              cs.server,
              _clientIdentifier,
            ).fetchMovieDetail(ratingKey),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return results.whereType<(PlexServer, PlexMovieDetail)>().firstOrNull;
  }

  // ---- Watchlist ----

  Future<void> _refreshWatchlist() async {
    final token = _accountToken;
    if (token == null) return;
    try {
      _watchlistItems = await PlexWatchlistApi(_clientIdentifier)
          .fetchWatchlist(token);
      notifyListeners();
    } catch (_) {
      // keep the last-known list
    }
    unawaited(_resolveWatchlistAvailability());
  }

  /// Screen 20: the watchlist belongs to the account, so it can hold titles
  /// on none of your servers — those stay in the grid, marked, rather than
  /// hidden or silently unplayable. Looks each entry up by guid on every
  /// connected server (the same lookup opening one uses).
  Future<void> _resolveWatchlistAvailability() async {
    final items = _watchlistItems ?? const <PlexWatchlistItem>[];
    final servers = _connectedServers;
    if (items.isEmpty || servers.isEmpty) return;
    final resolved = <String, String?>{};
    await Future.wait(
      items.map((entry) async {
        final guid = entry.guid;
        String? holder;
        if (guid != null) {
          for (final cs in servers) {
            try {
              final found = await PlexServerApi(
                cs.server,
                _clientIdentifier,
              ).fetchLibraryItemsByGuid(guid);
              if (found.isNotEmpty) {
                holder = cs.server.name;
                break;
              }
            } catch (_) {
              // An unanswering server just doesn't count as holding it.
            }
          }
        }
        resolved[entry.ratingKey] = holder;
      }),
    );
    _watchlistAvailability = resolved;
    notifyListeners();
  }

  bool isOnWatchlist(String? guid) =>
      guid != null && (_watchlistItems?.any((i) => i.guid == guid) ?? false);

  Future<void> toggleWatchlist(String? guid) async {
    final token = _accountToken;
    if (guid == null || token == null) return;
    final api = PlexWatchlistApi(_clientIdentifier);
    try {
      if (isOnWatchlist(guid)) {
        await api.removeFromWatchlist(token, guid);
      } else {
        await api.addToWatchlist(token, guid);
      }
    } catch (_) {}
    await _refreshWatchlist();
  }

  void removeFromWatchlist(PlexWatchlistItem entry) {
    _watchlistItems = _watchlistItems
        ?.where((i) => i.ratingKey != entry.ratingKey)
        .toList();
    notifyListeners();
    final token = _accountToken;
    final guid = entry.guid;
    if (token != null && guid != null) {
      unawaited(
        PlexWatchlistApi(_clientIdentifier)
            .removeFromWatchlist(token, guid)
            .catchError((_) {}),
      );
    }
  }

  // ---- Relay / live rooms ----

  Future<RelayClient?> _ensureRelayClient(
    String relayUrl,
    RoomIntent intent,
  ) async {
    final existing = _relayClient;
    if (existing != null) return existing;
    if (relayUrl.trim().isEmpty) return null;

    final identity = _relayIdentity ?? await _relayIdentityStore.load();
    _relayIdentity = identity;
    final client = RelayClient(
      relayUrl,
      identity,
      onIdentityUpdated: (updated) {
        _relayIdentity = updated;
        final token = updated.reconnectToken;
        if (token != null)
          unawaited(_relayIdentityStore.saveReconnectToken(token));
      },
      onHostedRoomIdUpdated: (hostedId, token) {
        unawaited(_relayIdentityStore.addHostedRoom(relayUrl, hostedId, token));
      },
    );
    client.connect(intent);
    _relayClient = client;
    _myRoomIdSub = client.roomId.listen((id) {
      _myRoomId = id;
      notifyListeners();
    });
    return client;
  }

  void releaseRelayClient() {
    _myRoomIdSub?.cancel();
    _myRoomIdSub = null;
    _myRoomId = null;
    _relayClient?.disconnect();
    _relayClient?.dispose();
    _relayClient = null;
  }

  void _startRoomPolling() {
    _roomPollTimer?.cancel();
    _pollRooms();
    _roomPollTimer = Timer.periodic(
      const Duration(milliseconds: _roomPollIntervalMs),
      (_) => _pollRooms(),
    );
  }

  void _stopRoomPolling() {
    _roomPollTimer?.cancel();
    _roomPollTimer = null;
    _liveRoomsByRelay = {};
    _relayHealth = {};
  }

  /// One directory round trip to [relayUrl], in ms — null if it didn't
  /// answer. The lobby (screen 10) shows it beside the relay's name; the
  /// room poll's own health is cleared whenever polling stops.
  Future<int?> measureRelayLatency(String relayUrl) async {
    final stopwatch = Stopwatch()..start();
    final rooms = await _relayDirectoryApi.tryListRooms(relayUrl);
    return rooms != null ? stopwatch.elapsedMilliseconds : null;
  }

  Future<void> _pollRooms() async {
    final settings = await _settingsStore.observe().first;
    final byUrl = groupBy(settings.relays, (RelayEntry e) => e.url);
    final relays = byUrl.values
        .map(
          (entries) =>
              entries.firstWhereOrNull((e) => e.isDefault) ?? entries.first,
        )
        .toList();

    _liveRelaysById = {for (final r in relays) r.id: r};
    final stillConfigured = relays.map((r) => r.id).toSet();
    _liveRoomsByRelay = Map.fromEntries(
      _liveRoomsByRelay.entries.where((e) => stillConfigured.contains(e.key)),
    );
    final identity = await _relayIdentityStore.load();
    _hostedRoomIds = identity.hostedRooms.map((r) => r.roomId).toSet();
    notifyListeners();

    for (final entry in relays) {
      if (_pollInFlight.contains(entry.id)) continue;
      _pollInFlight.add(entry.id);
      final stopwatch = Stopwatch()..start();
      unawaited(
        _relayDirectoryApi.tryListRooms(entry.url).then((rooms) {
          _pollInFlight.remove(entry.id);
          final previous = _relayHealth[entry.id];
          _relayHealth = {
            ..._relayHealth,
            entry.id: rooms != null
                ? RelayHealth.reachable(
                    latencyMs: stopwatch.elapsedMilliseconds,
                    at: DateTime.now(),
                  )
                : RelayHealth.unreachable(
                    lastAnsweredAt: previous?.lastAnsweredAt,
                  ),
          };
          _liveRoomsByRelay = {
            ..._liveRoomsByRelay,
            entry.id: rooms ?? const [],
          };
          notifyListeners();
        }),
      );
    }
  }

  Future<bool> closeHostedRoom(MergedRoom merged) async {
    final identity = await _relayIdentityStore.load();
    final hosted = identity.hostedRooms.firstWhereOrNull(
      (r) => r.roomId == merged.room.roomId,
    );
    if (hosted == null) return false;
    final ok = await _relayDirectoryApi.closeRoom(
      merged.relay.url,
      merged.room.roomId,
      identity.peerId,
      hosted.reconnectToken,
    );
    if (ok) {
      await _relayIdentityStore.removeHostedRoom(merged.room.roomId);
      _hostedRoomIds = {..._hostedRoomIds}..remove(merged.room.roomId);
      _liveRoomsByRelay = {
        for (final e in _liveRoomsByRelay.entries)
          e.key: e.value.where((r) => r.roomId != merged.room.roomId).toList(),
      };
      notifyListeners();
    }
    return ok;
  }

  Future<(RelayEntry, RelayRoomSummary)?> _findHostedRoomForMedia(
    String ratingKey,
  ) async {
    final identity = await _relayIdentityStore.load();
    if (identity.hostedRooms.isEmpty) return null;
    final hostedByRelay = groupBy(
      identity.hostedRooms,
      (HostedRoom r) => r.relayUrl,
    );
    final settings = await _settingsStore.observe().first;
    final relaysByUrl = {for (final r in settings.relays) r.url: r};

    for (final entry in hostedByRelay.entries) {
      final relayUrl = entry.key;
      final hostedIds = entry.value.map((r) => r.roomId).toSet();
      List<RelayRoomSummary> rooms;
      try {
        rooms = await _relayDirectoryApi.listRooms(relayUrl);
      } catch (_) {
        continue;
      }
      final match = rooms.firstWhereOrNull(
        (r) => r.ratingKey == ratingKey && hostedIds.contains(r.roomId),
      );
      if (match != null) {
        final relayEntry =
            relaysByUrl[relayUrl] ??
            RelayEntry(id: relayUrl, nickname: relayUrl, url: relayUrl);
        return (relayEntry, match);
      }
    }
    return null;
  }

  /// Opens screen 09 rather than starting the room immediately — the
  /// actual room creation is still [startWatchTogether] below, called once
  /// the dialog confirms. No network calls here; just a state change, so
  /// the dialog appears instantly. [server] is whichever server the shared
  /// content actually lives on (resolved by the caller from the specific
  /// copy on screen, e.g. a MovieDetail's Sourced movie) — a room is always
  /// hosted off one concrete file.
  void openWatchTogetherStart({
    required LibraryContext ctx,
    required PlexServer server,
    required AppState returnState,
    required String roomTitle,
    String? thumb,
    required String targetRatingKey,
    bool defaultRestart = false,
  }) {
    _setState(
      WatchTogetherStart(
        ctx: ctx,
        server: server,
        returnState: returnState,
        roomTitle: roomTitle,
        thumb: thumb,
        targetRatingKey: targetRatingKey,
        defaultRestart: defaultRestart,
      ),
    );
  }

  Future<void> startWatchTogether({
    required LibraryContext ctx,
    required PlexServer server,
    required AppState returnState,
    required String roomTitle,
    required String? thumb,
    required String targetRatingKey,
    required bool restart,
  }) async {
    final hostName =
        _activeProfile?.watchTogetherName ?? _localAccount?.username ?? 'Host';
    final settings = await _settingsStore.observe().first;
    final defaultRelay = settings.defaultRelay;
    if (defaultRelay == null) {
      _setState(
        Settings(
          ctx: ctx,
          returnState: returnState,
          relayHint: 'Add a relay to watch with friends.',
        ),
      );
      return;
    }

    final existing = await _findHostedRoomForMedia(targetRatingKey);
    final relay = existing != null
        ? await _ensureRelayClient(
            existing.$1.url,
            JoinRoom(existing.$2.roomId),
          )
        : await _ensureRelayClient(
            defaultRelay.url,
            CreateRoom(
              title: roomTitle,
              thumb: thumb,
              ratingKey: targetRatingKey,
              hostName: hostName,
              maxSeats: settings.maxHostSeats,
            ),
          );
    if (relay == null) {
      _setState(
        Settings(
          ctx: ctx,
          returnState: returnState,
          relayHint: 'Add a relay to watch with friends.',
        ),
      );
      return;
    }

    try {
      final detail = await PlexServerApi(
        server,
        _clientIdentifier,
      ).fetchMovieDetail(targetRatingKey);
      _setState(
        Lobby(
          server: server,
          detail: restart ? detail.copyWith(viewOffset: 0) : detail,
          returnState: returnState,
          relay: relay,
          hostName: existing?.$2.hostName ?? hostName,
          relayNickname: existing?.$1.nickname ?? defaultRelay.nickname,
          thumb: thumb,
          isHost: true,
        ),
      );
    } catch (e) {
      _setState(AppError(message: '$e', retryState: returnState));
    }
  }

  Future<void> hostOnAnotherRelay(Lobby current) async {
    final settings = await _settingsStore.observe().first;
    final next = settings.relays.firstWhereOrNull(
      (r) => r.url != current.relay.relayUrl,
    );
    if (next == null) return;
    releaseRelayClient();
    final hostName =
        _activeProfile?.watchTogetherName ?? _localAccount?.username ?? 'Host';
    final newClient = await _ensureRelayClient(
      next.url,
      CreateRoom(
        title: current.detail.title,
        thumb: current.thumb,
        ratingKey: current.detail.ratingKey,
        hostName: hostName,
        maxSeats: settings.maxHostSeats,
      ),
    );
    if (newClient != null) {
      _setState(
        Lobby(
          server: current.server,
          detail: current.detail,
          returnState: current.returnState,
          relay: newClient,
          hostName: hostName,
          relayNickname: next.nickname,
          thumb: current.thumb,
          isHost: true,
        ),
      );
    }
  }

  // ---- Library / Home navigation ----

  /// Fans every connected server's Home hubs out concurrently, merges, and
  /// folds each list by guid into one [Home] — a title on two servers is
  /// one card, not two (see duplicate_fold.dart). Each server's own four
  /// fetches keep their existing per-call `.catchError`, so one dead
  /// server never blocks or breaks another's contribution — mirrors the
  /// fan-out shape _pollRooms already uses for the (unrelated) relay
  /// directory. Recently Added is sorted by addedAt before folding/capping
  /// — concatenating per-server lists in server order (their fetch order)
  /// would otherwise interleave wrong once a second server contributes.
  Future<Home> _loadHome(
    List<ReachableServer> servers,
    List<SectionGroup> sectionGroups,
  ) async {
    final perServer = await Future.wait(
      servers.map((cs) async {
        final api = PlexServerApi(cs.server, _clientIdentifier);
        // All four hubs at once, not one after another.
        final (onDeck, recentlyAdded, recentActivity, suggestions) = await (
          api.fetchOnDeck().catchError((_) => <PlexOnDeckItem>[]),
          api.fetchRecentlyAdded().catchError((_) => <PlexLibraryItem>[]),
          api.fetchRecentActivity().catchError((_) => <PlexOnDeckItem>[]),
          api.fetchSuggestions().catchError((_) => <PlexOnDeckItem>[]),
        ).wait;
        return (cs, onDeck, recentlyAdded, recentActivity, suggestions);
      }),
    );

    final onDeck = <Sourced<PlexOnDeckItem>>[];
    final recentlyAdded = <Sourced<PlexLibraryItem>>[];
    final recentActivity = <Sourced<PlexOnDeckItem>>[];
    final suggestions = <Sourced<PlexOnDeckItem>>[];
    for (final (cs, od, ra, rac, sug) in perServer) {
      onDeck.addAll(od.map((i) => Sourced(i, cs.server, cs.reachability)));
      recentlyAdded.addAll(
        ra.map((i) => Sourced(i, cs.server, cs.reachability)),
      );
      recentActivity.addAll(
        rac.map((i) => Sourced(i, cs.server, cs.reachability)),
      );
      suggestions.addAll(
        sug.map((i) => Sourced(i, cs.server, cs.reachability)),
      );
    }
    recentlyAdded.sort(
      (a, b) => (b.value.addedAt ?? 0).compareTo(a.value.addedAt ?? 0),
    );

    return Home(
      servers: servers,
      sectionGroups: sectionGroups,
      onDeck: foldByGuid(
        onDeck,
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      ),
      recentlyAdded: foldByGuid(
        recentlyAdded,
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      ).take(15).toList(),
      recentActivity: foldByGuid(
        recentActivity,
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      ),
      suggestions: foldByGuid(
        suggestions,
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      ),
      unreachableResources: _unreachableResources,
    );
  }

  Future<void> goHome(
    List<ReachableServer> servers,
    List<SectionGroup> sectionGroups,
  ) async {
    _setState(LoadingHome(servers: servers, sectionGroups: sectionGroups));
    _setState(await _loadHome(servers, sectionGroups));
  }

  void selectSection(LibraryContext ctx, SectionGroup group) {
    // Reselecting the section already on screen is a no-op fetch-wise —
    // but only when there's actually something to reuse. If the first
    // load of this section ever came back empty (a slow server on cold
    // connect, a transient fetch failure — _fetchGroupItems swallows
    // per-server errors into an empty list same as everywhere else in
    // this app), skipping the shortcut here is what gives a later tap a
    // real chance to refetch, instead of replaying that stale empty
    // result forever.
    final current = _state;
    if (group.key == ctx.selectedSectionGroup.key &&
        ctx.items.isNotEmpty &&
        current is Library) {
      _setState(Library(ctx: ctx, returnState: current.returnState));
      return;
    }
    openSection(ctx.servers, ctx.sectionGroups, group);
  }

  void openSection(
    List<ReachableServer> servers,
    List<SectionGroup> sectionGroups,
    SectionGroup group,
  ) {
    final previous = _state;
    final loading = LoadingSection(
      servers: servers,
      sectionGroups: sectionGroups,
      selectedSectionGroupKey: group.key,
      returnState: previous,
    );
    _setState(loading);
    () async {
      final items = foldByGuid(
        await _fetchGroupItems(servers, group),
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      );
      // A slow fetch (e.g. a very large library) can outlast the user's
      // patience — BackHandler on LoadingSection lets them bail out via
      // returnState before this resolves. Don't clobber wherever they've
      // navigated to since with a stale result.
      if (identical(_state, loading)) {
        _setState(
          Library(
            ctx: LibraryContext(
              servers: servers,
              sectionGroups: sectionGroups,
              selectedSectionGroup: group,
              items: items,
            ),
            returnState: previous,
          ),
        );
      }
    }();
  }

  Future<AppState> _refreshReturnState(AppState target) async {
    if (target is Home) return _loadHome(target.servers, target.sectionGroups);
    if (target is Library) {
      final items = foldByGuid(
        await _fetchGroupItems(
          target.ctx.servers,
          target.ctx.selectedSectionGroup,
        ),
        guidOf: (i) => i.guid,
        alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
      );
      return Library(
        ctx: target.ctx.copyWith(items: items),
        returnState: target.returnState,
      );
    }
    return target;
  }

  void returnTo(AppState target) {
    _setState(target);
    () async {
      final refreshed = await _refreshReturnState(target);
      ScreenMemory.carry(target, refreshed);
      if (identical(_state, target)) _setState(refreshed);
    }();
  }

  void removeFromContinueWatching(Home home, FoldedWork<PlexOnDeckItem> work) {
    final target = work.primary;
    final updated = home.copyWith(
      onDeck: home.onDeck
          .where(
            (w) =>
                w.primary.server.machineIdentifier !=
                    target.server.machineIdentifier ||
                w.primary.value.ratingKey != target.value.ratingKey,
          )
          .toList(),
    );
    ScreenMemory.carry(home, updated);
    _setState(updated);
    unawaited(
      PlexServerApi(
        target.server,
        _clientIdentifier,
      ).removeFromContinueWatching(target.value.ratingKey).catchError((_) {}),
    );
  }

  // ---- Player entry points ----

  /// [server] is whichever server the specific copy being played actually
  /// lives on (the caller already knows this — a MovieDetail/EpisodeDetail
  /// screen holds a [Sourced] item, and [ctx] alone can no longer say
  /// "the" server now that it holds every connected one).
  Future<void> playMovie(
    LibraryContext? ctx,
    PlexServer server,
    String targetRatingKey,
    AppState returnState, {
    bool fromStart = false,
    String? showRatingKey,
    int? resumeAtMs,
  }) async {
    try {
      final detail = await PlexServerApi(
        server,
        _clientIdentifier,
      ).fetchMovieDetail(targetRatingKey);
      // Progress belongs to the title: another copy may have you further in
      // than this server does.
      final own = detail.viewOffset ?? 0;
      final at = fromStart ? 0 : max(own, resumeAtMs ?? 0);
      _setState(
        Player(
          ctx: ctx,
          server: server,
          detail: at == own ? detail : detail.copyWith(viewOffset: at),
          returnState: returnState,
          relay: null,
          showRatingKey: showRatingKey,
        ),
      );
    } catch (_) {
      // Screen 25 — name what failed plainly rather than the raw
      // exception; the actual cause is almost always "the server
      // stopped answering partway through starting", which is also the
      // one phrase from the mockup that's true regardless of the
      // specific underlying network error.
      _setState(
        PlaybackFailed(
          ctx: ctx,
          server: server,
          targetRatingKey: targetRatingKey,
          fromStart: fromStart,
          reason: '${server.name} stopped answering partway through starting',
          resumeAtMs: resumeAtMs,
          returnState: returnState,
        ),
      );
    }
  }

  /// Screen 25 from inside the player: the stream wouldn't open, or died
  /// partway through. Leaves any Watch Together room — retry plays solo —
  /// and carries [positionMs] so retry (or another copy) picks up there.
  void playbackFailed(Player state, String reason, {required int positionMs}) {
    releaseRelayClient();
    _setState(
      PlaybackFailed(
        ctx: state.ctx,
        server: state.server,
        targetRatingKey: state.detail.ratingKey,
        fromStart: false,
        reason: reason,
        returnState: state.returnState,
        resumeAtMs: positionMs,
      ),
    );
  }

  // ---- Home row navigation ----

  /// A Watch Together room only carries a ratingKey, never which server
  /// hosted it, so this is the one place content still has to be looked
  /// up across every connected server rather than already knowing its
  /// source — see _fetchMovieDetailFromAnyServer.
  /// Screen 12 opens over any screen, so [current] is whatever was showing
  /// (it becomes the error retry target and the lobby's return state) and
  /// [servers] is the hub the room's title is looked up across.
  Future<void> joinRoom(
    AppState current,
    List<ReachableServer> servers,
    MergedRoom merged,
  ) async {
    final ratingKey = merged.room.ratingKey;
    if (ratingKey == null) {
      _setState(
        AppError(message: 'Room has no movie reference', retryState: current),
      );
      return;
    }
    final found = await _fetchMovieDetailFromAnyServer(servers, ratingKey);
    if (found == null) {
      _setState(
        AppError(
          message: 'Could not find that title on any connected server',
          retryState: current,
        ),
      );
      return;
    }
    final (server, detail) = found;
    final relay = await _ensureRelayClient(
      merged.relay.url,
      JoinRoom(merged.room.roomId),
    );
    if (relay == null) {
      _setState(AppError(message: 'No relay configured', retryState: current));
      return;
    }
    final resolved = await relay.connectionState
        .firstWhere(
          (s) =>
              s == ConnectionState.connected ||
              s == ConnectionState.roomNotFound,
        )
        .timeout(
          const Duration(milliseconds: _joinRoomTimeoutMs),
          onTimeout: () => ConnectionState.disconnected,
        );
    if (resolved == ConnectionState.roomNotFound) {
      _setState(
        AppError(message: 'That room just ended.', retryState: current),
      );
    } else {
      _setState(
        Lobby(
          server: server,
          detail: detail,
          returnState: current,
          relay: relay,
          hostName: merged.room.hostName,
          relayNickname: merged.relay.nickname,
        ),
      );
    }
  }

  void resumeOnDeckItem(Home current, FoldedWork<PlexOnDeckItem> onDeckWork) {
    final activeOnDeck = onDeckWork.primary;
    final ctx = LibraryContext(
      servers: current.servers,
      sectionGroups: current.sectionGroups,
      selectedSectionGroup: sectionGroupFor(
        current.sectionGroups,
        activeOnDeck.value.type == 'episode'
            ? _sectionTypeShow
            : activeOnDeck.value.type,
      ),
      items: const [],
    );
    if (activeOnDeck.value.type == 'episode') {
      final work = _libraryWorkFrom(
        onDeckWork,
        (v) => libraryItemFrom(
          v,
          type: _sectionTypeShow,
          title: v.grandparentTitle ?? v.title,
        ),
      );
      _setState(
        EpisodeDetail(
          ctx: ctx,
          work: work,
          activeCopy: work.primary,
          episode: episodeFrom(activeOnDeck.value),
          returnState: current,
        ),
      );
    } else {
      final work = _libraryWorkFrom(onDeckWork, libraryItemFrom);
      _setState(
        MovieDetail(
          ctx: ctx,
          work: work,
          activeCopy: work.primary,
          returnState: current,
        ),
      );
    }
  }

  Future<void> selectWatchlistItem(Home current, PlexWatchlistItem entry) =>
      openWatchlistItem(
        servers: current.servers,
        sectionGroups: current.sectionGroups,
        entry: entry,
        returnState: current,
      );

  /// Resolves a watchlist entry (an account-wide Plex Discover guid, not
  /// tied to any one server) against every connected server's library by
  /// guid, fanned out concurrently, then picks the best-reachability copy
  /// via the same fold priority used everywhere duplicates are resolved
  /// (see duplicate_fold.dart) — the multi-server generalization of what
  /// this method used to do against just the one active server.
  Future<void> openWatchlistItem({
    required List<ReachableServer> servers,
    required List<SectionGroup> sectionGroups,
    required PlexWatchlistItem entry,
    required AppState returnState,
  }) async {
    final guid = entry.guid;
    final matches = <Sourced<PlexLibraryItem>>[];
    if (guid != null) {
      final results = await Future.wait(
        servers.map((cs) async {
          try {
            final items = await PlexServerApi(
              cs.server,
              _clientIdentifier,
            ).fetchLibraryItemsByGuid(guid);
            return items
                .map((i) => Sourced(i, cs.server, cs.reachability))
                .toList();
          } catch (_) {
            return const <Sourced<PlexLibraryItem>>[];
          }
        }),
      );
      matches.addAll(results.expand((l) => l));
    }
    if (matches.isEmpty) {
      _setState(
        AppError(
          message: '"${entry.title}" isn\'t in your Plex library yet.',
          retryState: returnState,
        ),
      );
      return;
    }
    final work = foldByGuid(
      matches,
      guidOf: (item) => item.guid,
      alternateIdsOf: (item) => item.guids.map((g) => g.id).toList(),
    ).first;
    final ctx = LibraryContext(
      servers: servers,
      sectionGroups: sectionGroups,
      selectedSectionGroup: sectionGroupFor(
        sectionGroups,
        work.primary.value.type ?? '',
      ),
      items: const [],
    );
    _setState(
      MovieDetail(
        ctx: ctx,
        work: work,
        activeCopy: work.primary,
        returnState: returnState,
      ),
    );
  }

  /// A season in Recently Added promotes to its parent show, same as
  /// before — applied only to [work]'s primary copy (a season's sibling
  /// copies on other servers could in principle need a different
  /// parentRatingKey; this is a rare enough edge case that the promoted
  /// result is a fresh singleton fold rather than trying to re-derive
  /// every copy's own parent).
  void selectRecentlyAdded(Home current, FoldedWork<PlexLibraryItem> work) {
    final primary = work.primary;
    final parentRatingKey = primary.value.parentRatingKey;
    final effectiveWork =
        primary.value.type == 'season' && parentRatingKey != null
        ? FoldedWork<PlexLibraryItem>(null, [
            Sourced(
              libraryItemFrom(
                PlexOnDeckItem(
                  ratingKey: parentRatingKey,
                  type: _sectionTypeShow,
                  title: primary.value.parentTitle ?? primary.value.title,
                  thumb: primary.value.thumb,
                  art: primary.value.art,
                ),
              ),
              primary.server,
              primary.reachability,
            ),
          ])
        : work;
    final ctx = LibraryContext(
      servers: current.servers,
      sectionGroups: current.sectionGroups,
      selectedSectionGroup: sectionGroupFor(
        current.sectionGroups,
        effectiveWork.primary.value.type ?? '',
      ),
      items: const [],
    );
    _setState(
      MovieDetail(
        ctx: ctx,
        work: effectiveWork,
        activeCopy: effectiveWork.primary,
        returnState: current,
      ),
    );
  }

  void selectOnDeckLike(Home current, FoldedWork<PlexOnDeckItem> onDeckWork) {
    final work = _libraryWorkFrom(onDeckWork, libraryItemFrom);
    final ctx = LibraryContext(
      servers: current.servers,
      sectionGroups: current.sectionGroups,
      selectedSectionGroup: sectionGroupFor(
        current.sectionGroups,
        work.primary.value.type ?? '',
      ),
      items: const [],
    );
    _setState(
      MovieDetail(
        ctx: ctx,
        work: work,
        activeCopy: work.primary,
        returnState: current,
      ),
    );
  }
}

/// Converts every copy of a [FoldedWork]&lt;PlexOnDeckItem&gt; through [convert]
/// into a library-item-shaped [FoldedWork], preserving the fold's guid and
/// copy set — used wherever a Home row's on-deck-shaped selection needs to
/// become a MovieDetail/EpisodeDetail work.
FoldedWork<PlexLibraryItem> _libraryWorkFrom(
  FoldedWork<PlexOnDeckItem> work,
  PlexLibraryItem Function(PlexOnDeckItem) convert,
) => FoldedWork(
  work.guid,
  work.copies
      .map((c) => Sourced(convert(c.value), c.server, c.reachability))
      .toList(),
);

/// Builds a `PlexLibraryItem`/show-typed placeholder from an on-deck-shaped
/// item (recently-added, suggestions, recent-activity, resume) so a
/// MovieDetail/EpisodeDetail navigation has something to
/// render immediately while the real detail loads.
PlexLibraryItem libraryItemFrom(
  PlexOnDeckItem item, {
  String? type,
  String? title,
}) => PlexLibraryItem(
  ratingKey: item.ratingKey,
  type: type ?? item.type,
  title: title ?? item.title,
  thumb: item.thumb,
  art: item.art,
  guid: item.guid,
  guids: item.guids,
);

PlexEpisode episodeFrom(PlexOnDeckItem item) => PlexEpisode(
  ratingKey: item.ratingKey,
  title: item.title,
  index: item.index,
  thumb: item.thumb,
  duration: item.duration,
  viewOffset: item.viewOffset,
  parentIndex: item.parentIndex,
  grandparentTitle: item.grandparentTitle,
);

/// Picks the section group matching an item's type, falling back to the
/// first group.
SectionGroup sectionGroupFor(List<SectionGroup> groups, String type) =>
    groups.firstWhereOrNull((g) => g.type == type) ?? groups.first;

/// Live rooms are polled on every screen the rooms panel (screen 12) can
/// open over — it used to be Home only, so a room opened while you were on
/// a detail page never showed in the panel until you went Home. Not while
/// signing in, nor in a lobby or the player, which hold a room of their
/// own and have no panel.
bool pollsLiveRooms(AppState state) => switch (state) {
  Checking() ||
  LoggedOut() ||
  ProfilePicker() ||
  ConnectingToServer() ||
  RelaySetup() ||
  Lobby() ||
  Player() => false,
  _ => true,
};

/// Mirrors settings_store.dart's `_randomRelayId` — same shape, separate
/// copy since that one's private to its own file.
String _randomProfileId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz';
  final random = Random.secure();
  return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
}
