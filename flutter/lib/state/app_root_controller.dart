import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/plex/plex_auth_api.dart';
import '../data/plex/plex_identity.dart';
import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart';
import '../data/plex/plex_server_api.dart';
import '../data/plex/plex_watchlist_api.dart';
import '../data/plex/secure_token_store.dart';
import '../data/settings/app_settings.dart';
import '../data/settings/relay_identity_store.dart';
import '../data/settings/settings_store.dart';
import '../screens/home/watch_together_row.dart';
import '../sync/relay_client.dart';
import '../sync/relay_directory_api.dart';
import '../sync/relay_protocol.dart';
import 'app_state.dart';

const _sectionTypeShow = 'show';
const _roomPollIntervalMs = 5000;
const _joinRoomTimeoutMs = 5000;

class _FriendlyError implements Exception {
  final String message;
  const _FriendlyError(this.message);
  @override
  String toString() => message;
}

/// Ports MainActivity.kt's `AppRoot` composable — every local `remember`ed
/// var there becomes a field here, every local `suspend fun`/closure
/// becomes a method. Kotlin's whole-composable-scope recomposition (any
/// `mutableStateOf` write triggers every reader to rebuild) is matched by
/// a single ChangeNotifier: everything above (state, account, watchlist,
/// live rooms) is one reactive surface here too, not split across several
/// Riverpod providers, since several screens (MovieDetail/EpisodeDetail's
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
    final wasHome = _state is Home;
    final isHome = next is Home;
    _state = next;
    if (isHome && !wasHome) {
      _startRoomPolling();
    } else if (!isHome && wasHome) {
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

  AppSettings get currentSettings => _settingsStore.current ?? const AppSettings();

  Future<void> saveBitratePreference(int kbps) {
    final updated = currentSettings.copyWith(maxVideoBitrateKbps: kbps);
    return _settingsStore.save(updated);
  }

  List<PlexWatchlistItem>? _watchlistItems;
  List<PlexWatchlistItem> get watchlist => _watchlistItems ?? const [];

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

  List<MergedRoom> get liveRooms => [
        for (final entry in _liveRoomsByRelay.entries)
          if (_liveRelaysById[entry.key] != null)
            for (final room in entry.value) MergedRoom(_liveRelaysById[entry.key]!, room),
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
    final token = await _tokenStore.loadToken();
    if (token == null) {
      _setState(const LoggedOut());
    } else {
      await connect(token);
    }
  }

  Future<void> connect(String token) async {
    _accountToken = token;
    _clientIdentifier = await _plexIdentity.getOrCreateClientIdentifier();
    final authApi = PlexAuthApi(_clientIdentifier);
    try {
      _localAccount = await authApi.fetchAccount(token);
    } catch (_) {
      _localAccount = null;
    }
    _setState(ConnectingToServer(username: _localAccount?.username));

    try {
      final settings = await _settingsStore.observe().first;
      final server = await PlexResourcesApi(_clientIdentifier)
          .findReachableServer(token, preferredMachineIdentifier: settings.selectedServerId);
      if (server == null) {
        throw const _FriendlyError("No reachable Plex server found — make sure it's online and reachable on this network.");
      }
      final serverApi = PlexServerApi(server, _clientIdentifier);
      final sections = await serverApi.fetchSections();
      final firstSection = sections.firstOrNull;
      if (firstSection == null) {
        throw _FriendlyError('No movie or show library found on ${server.name}');
      }
      final items = await serverApi.fetchLibraryItems(firstSection.key);
      final ctx = LibraryContext(server: server, sections: sections, selectedSection: firstSection, items: items);
      final relayConfigured = settings.relays.isNotEmpty;
      _setState(relayConfigured ? await _loadHome(server, sections) : RelaySetup(ctx: ctx));
    } catch (e) {
      _setState(AppError(message: '$e', retryState: const LoggedOut()));
    }
    unawaited(_refreshWatchlist());
  }

  /// Persists the chosen server (screen 06's switcher panel) and runs the
  /// same reconnect [connect] already does on startup — there's no lighter
  /// in-place swap of the active [PlexServer]; every AppState variant
  /// carries its own `server`/`ctx.server` copy (see app_state.dart), so a
  /// full reconnect is what actually replaces all of them consistently.
  Future<void> switchServer(String machineIdentifier) async {
    final settings = await _settingsStore.observe().first;
    await _settingsStore.save(settings.copyWith(selectedServerId: machineIdentifier));
    final token = _accountToken;
    if (token != null) await connect(token);
  }

  // ---- Watchlist ----

  Future<void> _refreshWatchlist() async {
    final token = _accountToken;
    if (token == null) return;
    try {
      _watchlistItems = await PlexWatchlistApi(_clientIdentifier).fetchWatchlist(token);
      notifyListeners();
    } catch (_) {
      // keep the last-known list, matching Kotlin's `.getOrNull() ?: watchlistItems`
    }
  }

  bool isOnWatchlist(String? guid) => guid != null && (_watchlistItems?.any((i) => i.guid == guid) ?? false);

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
    _watchlistItems = _watchlistItems?.where((i) => i.ratingKey != entry.ratingKey).toList();
    notifyListeners();
    final token = _accountToken;
    final guid = entry.guid;
    if (token != null && guid != null) {
      unawaited(PlexWatchlistApi(_clientIdentifier).removeFromWatchlist(token, guid).catchError((_) {}));
    }
  }

  // ---- Relay / live rooms ----

  Future<RelayClient?> _ensureRelayClient(String relayUrl, RoomIntent intent) async {
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
        if (token != null) unawaited(_relayIdentityStore.saveReconnectToken(token));
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
    _roomPollTimer = Timer.periodic(const Duration(milliseconds: _roomPollIntervalMs), (_) => _pollRooms());
  }

  void _stopRoomPolling() {
    _roomPollTimer?.cancel();
    _roomPollTimer = null;
    _liveRoomsByRelay = {};
  }

  Future<void> _pollRooms() async {
    final settings = await _settingsStore.observe().first;
    final byUrl = groupBy(settings.relays, (RelayEntry e) => e.url);
    final relays = byUrl.values.map((entries) => entries.firstWhereOrNull((e) => e.isDefault) ?? entries.first).toList();

    _liveRelaysById = {for (final r in relays) r.id: r};
    final stillConfigured = relays.map((r) => r.id).toSet();
    _liveRoomsByRelay = Map.fromEntries(_liveRoomsByRelay.entries.where((e) => stillConfigured.contains(e.key)));
    final identity = await _relayIdentityStore.load();
    _hostedRoomIds = identity.hostedRooms.map((r) => r.roomId).toSet();
    notifyListeners();

    for (final entry in relays) {
      if (_pollInFlight.contains(entry.id)) continue;
      _pollInFlight.add(entry.id);
      unawaited(_relayDirectoryApi.listRooms(entry.url).then((rooms) {
        _pollInFlight.remove(entry.id);
        _liveRoomsByRelay = {..._liveRoomsByRelay, entry.id: rooms};
        notifyListeners();
      }));
    }
  }

  Future<bool> closeHostedRoom(MergedRoom merged) async {
    final identity = await _relayIdentityStore.load();
    final hosted = identity.hostedRooms.firstWhereOrNull((r) => r.roomId == merged.room.roomId);
    if (hosted == null) return false;
    final ok = await _relayDirectoryApi.closeRoom(merged.relay.url, merged.room.roomId, identity.peerId, hosted.reconnectToken);
    if (ok) {
      await _relayIdentityStore.removeHostedRoom(merged.room.roomId);
      _hostedRoomIds = {..._hostedRoomIds}..remove(merged.room.roomId);
      _liveRoomsByRelay = {
        for (final e in _liveRoomsByRelay.entries) e.key: e.value.where((r) => r.roomId != merged.room.roomId).toList(),
      };
      notifyListeners();
    }
    return ok;
  }

  Future<(RelayEntry, RelayRoomSummary)?> _findHostedRoomForMedia(String ratingKey) async {
    final identity = await _relayIdentityStore.load();
    if (identity.hostedRooms.isEmpty) return null;
    final hostedByRelay = groupBy(identity.hostedRooms, (HostedRoom r) => r.relayUrl);
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
      final match = rooms.firstWhereOrNull((r) => r.ratingKey == ratingKey && hostedIds.contains(r.roomId));
      if (match != null) {
        final relayEntry = relaysByUrl[relayUrl] ?? RelayEntry(id: relayUrl, nickname: relayUrl, url: relayUrl);
        return (relayEntry, match);
      }
    }
    return null;
  }

  Future<void> startWatchTogether({
    required LibraryContext ctx,
    required AppState returnState,
    required String roomTitle,
    required String? thumb,
    required String targetRatingKey,
    required bool restart,
  }) async {
    final hostName = _localAccount?.username ?? 'Host';
    final settings = await _settingsStore.observe().first;
    final defaultRelay = settings.defaultRelay;
    if (defaultRelay == null) {
      _setState(Settings(ctx: ctx, returnState: returnState, relayHint: 'Add a relay to watch with friends.'));
      return;
    }

    final existing = await _findHostedRoomForMedia(targetRatingKey);
    final relay = existing != null
        ? await _ensureRelayClient(existing.$1.url, JoinRoom(existing.$2.roomId))
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
      _setState(Settings(ctx: ctx, returnState: returnState, relayHint: 'Add a relay to watch with friends.'));
      return;
    }

    try {
      final detail = await PlexServerApi(ctx.server, _clientIdentifier).fetchMovieDetail(targetRatingKey);
      _setState(Lobby(
        server: ctx.server,
        detail: restart ? detail.copyWith(viewOffset: 0) : detail,
        returnState: returnState,
        relay: relay,
        hostName: existing?.$2.hostName ?? hostName,
        relayNickname: existing?.$1.nickname ?? defaultRelay.nickname,
        thumb: thumb,
        isHost: true,
      ));
    } catch (e) {
      _setState(AppError(message: '$e', retryState: returnState));
    }
  }

  Future<void> hostOnAnotherRelay(Lobby current) async {
    final settings = await _settingsStore.observe().first;
    final next = settings.relays.firstWhereOrNull((r) => r.url != current.relay.relayUrl);
    if (next == null) return;
    releaseRelayClient();
    final hostName = _localAccount?.username ?? 'Host';
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
      _setState(Lobby(
        server: current.server,
        detail: current.detail,
        returnState: current.returnState,
        relay: newClient,
        hostName: hostName,
        relayNickname: next.nickname,
        thumb: current.thumb,
        isHost: true,
      ));
    }
  }

  // ---- Library / Home navigation ----

  Future<Home> _loadHome(PlexServer server, List<PlexSection> sections) async {
    final api = PlexServerApi(server, _clientIdentifier);
    final onDeck = await api.fetchOnDeck().catchError((_) => <PlexOnDeckItem>[]);
    final recentlyAdded = await api.fetchRecentlyAdded().catchError((_) => <PlexLibraryItem>[]);
    final recentActivity = await api.fetchRecentActivity().catchError((_) => <PlexOnDeckItem>[]);
    final suggestions = await api.fetchSuggestions().catchError((_) => <PlexOnDeckItem>[]);
    return Home(
      server: server,
      sections: sections,
      onDeck: onDeck,
      recentlyAdded: recentlyAdded.take(15).toList(),
      recentActivity: recentActivity,
      suggestions: suggestions,
    );
  }

  Future<void> goHome(PlexServer server, List<PlexSection> sections) async {
    _setState(LoadingHome(server: server, sections: sections));
    _setState(await _loadHome(server, sections));
  }

  void selectSection(LibraryContext ctx, PlexSection section) {
    if (section.key == ctx.selectedSection.key) {
      _setState(Library(ctx: ctx));
      return;
    }
    openSection(ctx.server, ctx.sections, section);
  }

  void openSection(PlexServer server, List<PlexSection> sections, PlexSection section) {
    final previous = _state;
    final loading = LoadingSection(server: server, sections: sections, selectedSectionKey: section.key, returnState: previous);
    _setState(loading);
    () async {
      List<PlexLibraryItem> items;
      try {
        items = await PlexServerApi(server, _clientIdentifier).fetchLibraryItems(section.key);
      } catch (_) {
        items = const [];
      }
      // A slow fetch (e.g. a very large library) can outlast the user's
      // patience — BackHandler on LoadingSection lets them bail out via
      // returnState before this resolves. Don't clobber wherever they've
      // navigated to since with a stale result.
      if (identical(_state, loading)) {
        _setState(Library(ctx: LibraryContext(server: server, sections: sections, selectedSection: section, items: items)));
      }
    }();
  }

  Future<AppState> _refreshReturnState(AppState target) async {
    if (target is Home) return _loadHome(target.server, target.sections);
    if (target is Library) {
      try {
        final items = await PlexServerApi(target.ctx.server, _clientIdentifier).fetchLibraryItems(target.ctx.selectedSection.key);
        return Library(ctx: target.ctx.copyWith(items: items));
      } catch (_) {
        return target;
      }
    }
    return target;
  }

  void returnTo(AppState target) {
    _setState(target);
    () async {
      final refreshed = await _refreshReturnState(target);
      if (identical(_state, target)) _setState(refreshed);
    }();
  }

  void removeFromContinueWatching(Home home, PlexOnDeckItem item) {
    _setState(home.copyWith(onDeck: home.onDeck.where((i) => i.ratingKey != item.ratingKey).toList()));
    unawaited(PlexServerApi(home.server, _clientIdentifier).removeFromContinueWatching(item.ratingKey).catchError((_) {}));
  }

  // ---- Player entry points ----

  Future<void> playMovie(LibraryContext ctx, String targetRatingKey, AppState returnState, {bool fromStart = false}) async {
    try {
      final detail = await PlexServerApi(ctx.server, _clientIdentifier).fetchMovieDetail(targetRatingKey);
      _setState(Player(
        server: ctx.server,
        detail: fromStart ? detail.copyWith(viewOffset: 0) : detail,
        returnState: returnState,
        relay: null,
      ));
    } catch (e) {
      _setState(AppError(message: '$e', retryState: returnState));
    }
  }

  // ---- Home row navigation (ports MainActivity.kt's inline HomeScreen callbacks) ----

  Future<void> joinRoom(Home current, MergedRoom merged) async {
    final ratingKey = merged.room.ratingKey;
    if (ratingKey == null) {
      _setState(AppError(message: 'Room has no movie reference', retryState: current));
      return;
    }
    PlexMovieDetail detail;
    try {
      detail = await PlexServerApi(current.server, _clientIdentifier).fetchMovieDetail(ratingKey);
    } catch (e) {
      _setState(AppError(message: '$e', retryState: current));
      return;
    }
    final relay = await _ensureRelayClient(merged.relay.url, JoinRoom(merged.room.roomId));
    if (relay == null) {
      _setState(AppError(message: 'No relay configured', retryState: current));
      return;
    }
    final resolved = await relay.connectionState
        .firstWhere((s) => s == ConnectionState.connected || s == ConnectionState.roomNotFound)
        .timeout(const Duration(milliseconds: _joinRoomTimeoutMs), onTimeout: () => ConnectionState.disconnected);
    if (resolved == ConnectionState.roomNotFound) {
      _setState(AppError(message: 'That room just ended.', retryState: current));
    } else {
      _setState(Lobby(
        server: current.server,
        detail: detail,
        returnState: current,
        relay: relay,
        hostName: merged.room.hostName,
        relayNickname: merged.relay.nickname,
      ));
    }
  }

  void resumeOnDeckItem(Home current, PlexOnDeckItem item) {
    if (item.type == 'episode') {
      final show = libraryItemFrom(item, type: _sectionTypeShow, title: item.grandparentTitle ?? item.title);
      final ctx = LibraryContext(
        server: current.server,
        sections: current.sections,
        selectedSection: sectionFor(current.sections, _sectionTypeShow),
        items: const [],
      );
      _setState(EpisodeDetail(ctx: ctx, show: show, episode: episodeFrom(item), returnState: current));
    } else {
      final movie = libraryItemFrom(item);
      final ctx = LibraryContext(
        server: current.server,
        sections: current.sections,
        selectedSection: sectionFor(current.sections, item.type),
        items: const [],
      );
      _setState(MovieDetail(ctx: ctx, movie: movie, returnState: current));
    }
  }

  Future<void> selectWatchlistItem(Home current, PlexWatchlistItem entry) async {
    final guid = entry.guid;
    List<PlexLibraryItem> matches = const [];
    if (guid != null) {
      try {
        matches = await PlexServerApi(current.server, _clientIdentifier).fetchLibraryItemsByGuid(guid);
      } catch (_) {}
    }
    final match = matches.firstOrNull;
    if (match == null) {
      _setState(AppError(message: '"${entry.title}" isn\'t in your Plex library yet.', retryState: current));
      return;
    }
    final ctx = LibraryContext(
      server: current.server,
      sections: current.sections,
      selectedSection: sectionFor(current.sections, match.type ?? ''),
      items: const [],
    );
    _setState(MovieDetail(ctx: ctx, movie: match, returnState: current));
  }

  void selectRecentlyAdded(Home current, PlexLibraryItem item) {
    final parentRatingKey = item.parentRatingKey;
    final target = item.type == 'season' && parentRatingKey != null
        ? libraryItemFrom(
            PlexOnDeckItem(ratingKey: parentRatingKey, type: _sectionTypeShow, title: item.parentTitle ?? item.title, thumb: item.thumb, art: item.art),
          )
        : item;
    final ctx = LibraryContext(
      server: current.server,
      sections: current.sections,
      selectedSection: sectionFor(current.sections, target.type ?? ''),
      items: const [],
    );
    _setState(MovieDetail(ctx: ctx, movie: target, returnState: current));
  }

  void selectOnDeckLike(Home current, PlexOnDeckItem item) {
    final ctx = LibraryContext(
      server: current.server,
      sections: current.sections,
      selectedSection: sectionFor(current.sections, item.type),
      items: const [],
    );
    _setState(MovieDetail(ctx: ctx, movie: libraryItemFrom(item), returnState: current));
  }
}

/// Builds a `PlexLibraryItem`/show-typed placeholder from an on-deck-shaped
/// item — ports the manual reconstruction MainActivity.kt does at several
/// onSelect callbacks (recently-added, suggestions, recent-activity,
/// resume) so a MovieDetail/EpisodeDetail navigation has something to
/// render immediately while the real detail loads.
PlexLibraryItem libraryItemFrom(PlexOnDeckItem item, {String? type, String? title}) => PlexLibraryItem(
      ratingKey: item.ratingKey,
      type: type ?? item.type,
      title: title ?? item.title,
      thumb: item.thumb,
      art: item.art,
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

/// Picks the section matching an item's type, falling back to the first
/// section — mirrors the `sections.firstOrNull { it.type == X } ?:
/// sections.first()` pattern repeated throughout MainActivity.kt.
PlexSection sectionFor(List<PlexSection> sections, String type) =>
    sections.firstWhereOrNull((s) => s.type == type) ?? sections.first;
