import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart';
import '../data/plex/plex_server_api.dart';
import '../focus/back_handler.dart';
import '../kit/text.dart';
import '../state/app_root_controller.dart';
import '../state/app_state.dart';
import '../state/data_providers.dart';
import '../state/duplicate_fold.dart';
import '../sync/relay_directory_api.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'auth/auth_screen.dart';
import 'common/loading_screen.dart';
import 'common/no_servers_screen.dart';
import 'common/playback_failed_screen.dart';
import 'home/home_loading_skeleton.dart';
import 'home/home_screen.dart';
import 'library/collection_detail_screen.dart';
import 'library/episode_detail_screen.dart';
import 'library/library_screen.dart';
import 'library/movie_detail_screen.dart';
import 'library/person_filmography_screen.dart';
import 'library/search_screen.dart';
import 'library/show_detail_screen.dart';
import 'library/watchlist_screen.dart';
import 'lobby/lobby_screen.dart';
import 'lobby/watch_together_start_screen.dart';
import 'navigation/app_navigation_drawer.dart';
import 'player/player_screen.dart';
import 'profiles/profile_picker_screen.dart';
import 'settings/relay_setup_screen.dart';
import 'settings/settings_screen.dart';
import 'splash/splash_screen.dart';

const _sectionTypeShow = 'show';
const _appVersionName = '0.3.0';

const _splashMinHoldMs = 1400;
const _splashCrossfadeDuration = Duration(milliseconds: 200);

/// Renders whichever AppState is current, plus the splash-hold shell logic
/// ported from MainActivity.kt's AppRoot: splash stays up at minimum
/// SPLASH_MIN_HOLD_MS regardless of how fast the initial auth check
/// resolves, decoupled from it via a separate timer, then crossfades out.
/// Every screen and callback below is wired to [AppRootController] — see
/// that file for the actual business logic (each method there is a direct
/// port of one of MainActivity.kt's local closures).
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  bool _showSplash = true;
  final int _splashStartMs = DateTime.now().millisecondsSinceEpoch;
  bool _startedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (_startedOnce) return;
    _startedOnce = true;
    ref.read(appRootControllerProvider).start();
  }

  void _maybeHideSplash(AppState state) {
    if (!_showSplash) return;
    if (state is Checking || state is ConnectingToServer) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - _splashStartMs;
    final remaining = _splashMinHoldMs - elapsed;
    // Always defer, even when remaining <= 0 — this runs inside
    // ListenableBuilder's builder callback (i.e. during AppRoot's own
    // build), and calling setState synchronously there throws
    // "setState() or markNeedsBuild() called during build".
    Future.delayed(remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero, () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appRootControllerProvider);

    return ColoredBox(
      color: AppColors.background,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          _maybeHideSplash(controller.state);
          return AnimatedSwitcher(
            duration: _splashCrossfadeDuration,
            child: _showSplash
                ? const SplashScreen(key: ValueKey('splash'))
                : KeyedSubtree(key: const ValueKey('content'), child: _AppContent(controller: controller)),
          );
        },
      ),
    );
  }
}

/// Split out from [_AppRootState] so the splash-hold bookkeeping above
/// doesn't get lost in the size of the state switch below.
class _AppContent extends StatelessWidget {
  final AppRootController controller;

  const _AppContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return switch (state) {
      Checking() => const LoadingScreen(),
      ConnectingToServer(:final username) =>
        LoadingScreen(username != null ? 'Logged in as $username — connecting to library…' : 'Connecting to library…'),
      LoggedOut() => AuthScreen(onLoggedIn: controller.completeFirstLogin),
      ProfilePicker(:final profiles) => ProfilePickerScreen(
          profiles: profiles,
          onSelectProfile: controller.selectProfile,
          onAddProfile: controller.addProfileAndActivate,
        ),
      NoServersReachable(:final token, :final resources) => NoServersScreen(
          resources: resources,
          onRetry: () => controller.connect(token),
          onStartOver: () => controller.returnTo(const LoggedOut()),
        ),
      PlaybackFailed(:final ctx, :final server, :final targetRatingKey, :final fromStart, :final reason, :final returnState) => PlaybackFailedScreen(
          reason: reason,
          onRetry: () => controller.playMovie(ctx, server, targetRatingKey, returnState, fromStart: fromStart),
          onBack: () => controller.returnTo(returnState),
        ),
      AppError(:final message, :final retryState) => BackHandler(
          onBack: () => controller.returnTo(retryState),
          child: ColoredBox(
            color: AppColors.background,
            child: Center(child: AppText('Error: $message', style: AppTypography.body)),
          ),
        ),
      RelaySetup(:final ctx) => RelaySetupScreen(onDone: () => controller.goHome(ctx.servers, ctx.sectionGroups)),
      Home() => _buildHome(state),
      Library(:final ctx) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: LibraryScreen(
            servers: ctx.servers,
            selectedSectionGroup: ctx.selectedSectionGroup,
            items: ctx.items,
            onSelectItem: (item) => controller.returnTo(MovieDetail(ctx: ctx, work: item, activeCopy: item.primary, returnState: Library(ctx: ctx))),
            loadCollections: () => _fetchGroupCollections(ctx),
            onSelectCollection: (collection) => _openCollection(ctx, collection),
          ),
        ),
      LoadingSection(:final sectionGroups, :final selectedSectionGroupKey, :final returnState) => BackHandler(
          onBack: () => controller.returnTo(returnState),
          child: AppNavigationDrawer(
            sectionGroups: sectionGroups,
            selectedSectionGroupKey: selectedSectionGroupKey,
            isSettingsSelected: false,
            isHomeSelected: false,
            onSelectSection: (_) {},
            onOpenSettings: () {},
            onOpenHome: () {},
            onOpenSearch: () {},
            account: controller.localAccount,
            versionName: _appVersionName,
            connectedServers: controller.connectedServers,
            disabledServerIds: controller.currentSettings.disabledServerIds,
            loadServers: _loadServers,
            probeServer: _probeServer,
            loadLibraryCount: _loadLibraryCount,
            onToggleServer: _toggleServer,
            child: const LoadingScreen(),
          ),
        ),
      LoadingHome(:final sectionGroups) => AppNavigationDrawer(
          sectionGroups: sectionGroups,
          selectedSectionGroupKey: null,
          isSettingsSelected: false,
          isHomeSelected: true,
          onSelectSection: (_) {},
          onOpenSettings: () {},
          onOpenHome: () {},
          onOpenSearch: () {},
          account: controller.localAccount,
          versionName: _appVersionName,
          connectedServers: controller.connectedServers,
          disabledServerIds: controller.currentSettings.disabledServerIds,
          loadServers: _loadServers,
          probeServer: _probeServer,
          loadLibraryCount: _loadLibraryCount,
          onToggleServer: _toggleServer,
          child: const HomeLoadingSkeleton(),
        ),
      Settings(:final ctx, :final returnState, :final relayHint) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          isSettingsSelected: true,
          child: SettingsScreen(
            accountToken: controller.accountTokenOrEmpty,
            clientIdentifier: controller.clientIdentifier,
            hint: relayHint,
            onBack: () => controller.returnTo(returnState),
            onSaved: () {
              final token = controller.accountToken;
              if (token != null) {
                controller.connect(token);
              } else {
                controller.returnTo(returnState);
              }
            },
          ),
        ),
      Search(:final ctx, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          isSearchSelected: true,
          child: SearchScreen(
            servers: ctx.servers,
            search: (query) => _fanOutSearch(ctx, query),
            onSelectResult: (item) {
              final work = _libraryWorkFrom(item, libraryItemFrom);
              controller.returnTo(
                MovieDetail(
                  ctx: ctx.copyWith(selectedSectionGroup: sectionGroupFor(ctx.sectionGroups, work.primary.value.type ?? '')),
                  work: work,
                  activeCopy: work.primary,
                  returnState: state,
                ),
              );
            },
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      Watchlist(:final ctx) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: WatchlistScreen(
            items: controller.watchlist,
            onSelectItem: (entry) => controller.openWatchlistItem(
              servers: ctx.servers,
              sectionGroups: ctx.sectionGroups,
              entry: entry,
              returnState: state,
            ),
            onRemove: controller.removeFromWatchlist,
          ),
        ),
      MovieDetail(:final ctx, :final work, :final activeCopy, :final returnState) when ctx.selectedSectionGroup.type == _sectionTypeShow => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: ShowDetailScreen(
            server: activeCopy.server,
            show: activeCopy.value,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            resolveNextEpisode: () async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchNextEpisodeForShow(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadDetail: () async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchMovieDetail(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadSeasons: () async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchSeasons(activeCopy.value.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            loadEpisodes: (seasonRatingKey) async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchEpisodes(seasonRatingKey);
              } catch (_) {
                return const [];
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(ctx, activeCopy.server, targetRatingKey, state),
            onWatchTogether: (targetRatingKey) => controller.openWatchTogetherStart(
              ctx: ctx,
              server: activeCopy.server,
              returnState: state,
              roomTitle: activeCopy.value.title,
              thumb: activeCopy.value.thumb,
              targetRatingKey: targetRatingKey,
            ),
            onSelectEpisode: (episode) => controller.returnTo(EpisodeDetail(ctx: ctx, work: work, activeCopy: activeCopy, episode: episode, returnState: state)),
          ),
        ),
      MovieDetail(:final ctx, :final work, :final activeCopy, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: MovieDetailScreen(
            server: activeCopy.server,
            movie: activeCopy.value,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadDetail: () async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchMovieDetail(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadRelatedHubs: () async {
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchRelatedHubs(activeCopy.value.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            loadByActor: (actorId) async {
              final section = ctx.selectedSectionGroup.sectionOn(activeCopy.server.machineIdentifier);
              if (section == null) return const [];
              try {
                return await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchLibraryItemsByActor(section.key, actorId);
              } catch (_) {
                return const [];
              }
            },
            onSelectRelated: (item) {
              final newWork = FoldedWork<PlexLibraryItem>(item.guid, [Sourced(libraryItemFrom(item), activeCopy.server, activeCopy.reachability)]);
              controller.returnTo(
                MovieDetail(
                  ctx: ctx,
                  work: newWork,
                  activeCopy: newWork.primary,
                  returnState: MovieDetail(ctx: ctx, work: work, activeCopy: activeCopy, returnState: returnState),
                ),
              );
            },
            onSelectPerson: (person) async {
              final actorId = person.id;
              final section = ctx.selectedSectionGroup.sectionOn(activeCopy.server.machineIdentifier);
              try {
                final items = actorId == null || section == null
                    ? const <PlexLibraryItem>[]
                    : await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchLibraryItemsByActor(section.key, actorId);
                controller.returnTo(PersonFilmography(ctx: ctx, server: activeCopy.server, person: person, items: items, returnState: state));
              } catch (e) {
                controller.returnTo(AppError(message: '$e', retryState: state));
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(ctx, activeCopy.server, targetRatingKey, state),
            onWatchTogether: (targetRatingKey) => controller.openWatchTogetherStart(
              ctx: ctx,
              server: activeCopy.server,
              returnState: state,
              roomTitle: activeCopy.value.title,
              thumb: activeCopy.value.thumb,
              targetRatingKey: targetRatingKey,
            ),
            onRestartSolo: (targetRatingKey) => controller.playMovie(ctx, activeCopy.server, targetRatingKey, state, fromStart: true),
          ),
        ),
      PersonFilmography(:final ctx, :final server, :final person, :final items, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: PersonFilmographyScreen(
            server: server,
            personName: person.tag,
            personThumb: person.thumb,
            items: items,
            onSelectItem: (item) {
              final work = FoldedWork<PlexLibraryItem>(item.guid, [Sourced(item, server, _reachabilityOf(ctx, server))]);
              controller.returnTo(MovieDetail(ctx: ctx, work: work, activeCopy: work.primary, returnState: state));
            },
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      CollectionDetail(:final ctx, :final collection, :final items, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: CollectionDetailScreen(
            server: collection.server,
            collection: collection.value,
            items: items,
            onSelectItem: (item) {
              final work = FoldedWork<PlexLibraryItem>(item.guid, [Sourced(item, collection.server, collection.reachability)]);
              controller.returnTo(MovieDetail(ctx: ctx, work: work, activeCopy: work.primary, returnState: state));
            },
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      EpisodeDetail(:final ctx, :final activeCopy, :final episode, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: EpisodeDetailScreen(
            server: activeCopy.server,
            showTitle: activeCopy.value.title,
            episode: episode,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadShowGuid: () async {
              try {
                return (await PlexServerApi(activeCopy.server, controller.clientIdentifier).fetchMovieDetail(activeCopy.value.ratingKey)).guid;
              } catch (_) {
                return null;
              }
            },
            onPlay: () => controller.playMovie(ctx, activeCopy.server, episode.ratingKey, state, showRatingKey: activeCopy.value.ratingKey),
            onPlayFromStart: () => controller.playMovie(ctx, activeCopy.server, episode.ratingKey, state, fromStart: true, showRatingKey: activeCopy.value.ratingKey),
            onWatchTogether: () => controller.openWatchTogetherStart(
              ctx: ctx,
              server: activeCopy.server,
              returnState: state,
              roomTitle: _episodeRoomTitle(activeCopy.value, episode),
              thumb: episode.thumb,
              targetRatingKey: episode.ratingKey,
            ),
            onRestartTogether: () => controller.openWatchTogetherStart(
              ctx: ctx,
              server: activeCopy.server,
              returnState: state,
              roomTitle: _episodeRoomTitle(activeCopy.value, episode),
              thumb: episode.thumb,
              targetRatingKey: episode.ratingKey,
              defaultRestart: true,
            ),
          ),
        ),
      WatchTogetherStart(:final ctx, :final server, :final returnState, :final roomTitle, :final thumb, :final targetRatingKey, :final defaultRestart) =>
        WatchTogetherStartScreen(
          roomTitle: roomTitle,
          defaultRestart: defaultRestart,
          maxSeats: controller.currentSettings.maxHostSeats,
          relayNickname: controller.currentSettings.defaultRelay?.nickname,
          checkRelayReachable: controller.currentSettings.defaultRelay == null
              ? null
              : () => RelayDirectoryApi().testReachable(controller.currentSettings.defaultRelay!.url),
          onConfirm: ({required restart, required showPhoneChat}) => controller.startWatchTogether(
            ctx: ctx,
            server: server,
            returnState: returnState,
            roomTitle: roomTitle,
            thumb: thumb,
            targetRatingKey: targetRatingKey,
            restart: restart,
          ),
          onCancel: () => controller.returnTo(returnState),
        ),
      Lobby(:final detail, :final returnState, :final relay, :final hostName, :final relayNickname, :final isHost) => LobbyScreen(
          key: ValueKey('lobby-${detail.ratingKey}'),
          server: state.server,
          detail: detail,
          localUsername: controller.localAccount?.username ?? 'You',
          localAvatarUrl: controller.localAccount?.thumb,
          hostName: hostName,
          relayNickname: relayNickname,
          relay: relay,
          onHostOnAnother: isHost ? () => controller.hostOnAnotherRelay(state) : null,
          onStart: (restartFromBeginning) => controller.returnTo(
            Player(server: state.server, detail: restartFromBeginning ? detail.copyWith(viewOffset: 0) : detail, returnState: returnState, relay: relay),
          ),
          onBack: () {
            controller.releaseRelayClient();
            controller.returnTo(returnState);
          },
        ),
      Player(:final detail, :final returnState, :final relay, :final showRatingKey) => PlayerScreen(
          key: ValueKey('player-${detail.ratingKey}'),
          server: state.server,
          detail: detail,
          clientIdentifier: controller.clientIdentifier,
          relay: relay,
          settings: controller.currentSettings,
          onBitrateChanged: controller.saveBitratePreference,
          onExit: () {
            controller.releaseRelayClient();
            controller.returnTo(returnState);
          },
          // Screen 16 — only real when we actually know the show (see
          // Player.showRatingKey's doc comment: null for movies, and the
          // "next episode" lookup needs a LibraryContext to actually play
          // it, which only exists when returnState is the EpisodeDetail we
          // came from).
          loadNextEpisode: showRatingKey == null
              ? null
              : () => PlexServerApi(state.server, controller.clientIdentifier).fetchNextEpisodeForShow(showRatingKey),
          onPlayNext: returnState is EpisodeDetail
              ? (next) => controller.playMovie(returnState.ctx, state.server, next.ratingKey, returnState, showRatingKey: showRatingKey)
              : null,
        ),
    };
  }

  Widget _buildHome(Home home) {
    LibraryContext emptyCtx(SectionGroup group) => LibraryContext(
          servers: home.servers,
          sectionGroups: home.sectionGroups,
          selectedSectionGroup: group,
          items: const [],
        );

    return AppNavigationDrawer(
      sectionGroups: home.sectionGroups,
      isSettingsSelected: false,
      isHomeSelected: true,
      onSelectSection: (group) => controller.openSection(home.servers, home.sectionGroups, group),
      onOpenSettings: () => controller.returnTo(Settings(ctx: emptyCtx(home.sectionGroups.first), returnState: home)),
      onOpenSearch: () => controller.returnTo(Search(ctx: emptyCtx(home.sectionGroups.first), returnState: home)),
      onOpenWatchlist: () => controller.returnTo(Watchlist(ctx: emptyCtx(home.sectionGroups.first))),
      // Clicking Home while already on Home used to be a pure no-op —
      // no state change at all means nothing ever reclaims focus from the
      // nav rail, so the drawer never collapses back down (it only
      // collapses on focus loss). Reloading Home, same as every other
      // sidebar item does even when re-selecting its own current screen,
      // gives HomeScreen a real remount and its existing autofocus does
      // the rest.
      onOpenHome: () => controller.goHome(home.servers, home.sectionGroups),
      account: controller.localAccount,
      versionName: _appVersionName,
      connectedServers: controller.connectedServers,
      disabledServerIds: controller.currentSettings.disabledServerIds,
      loadServers: _loadServers,
      probeServer: _probeServer,
      loadLibraryCount: _loadLibraryCount,
      onToggleServer: _toggleServer,
      child: HomeScreen(
        servers: home.servers,
        unreachableResources: home.unreachableResources,
        onDeck: home.onDeck,
        recentlyAdded: home.recentlyAdded,
        recentActivity: home.recentActivity,
        suggestions: home.suggestions,
        watchlist: controller.watchlist,
        liveRooms: controller.liveRooms,
        myRoomId: controller.myRoomId,
        hostedRoomIds: controller.hostedRoomIds,
        onEndSession: controller.closeHostedRoom,
        onSelectRoom: (merged) => controller.joinRoom(home, merged),
        onResume: (item) => controller.resumeOnDeckItem(home, item),
        onRemove: (item) => controller.removeFromContinueWatching(home, item),
        onSelectWatchlistItem: (entry) => controller.selectWatchlistItem(home, entry),
        onRemoveFromWatchlist: controller.removeFromWatchlist,
        onSelectRecentlyAdded: (item) => controller.selectRecentlyAdded(home, item),
        onSelectRecentActivity: (item) => controller.selectOnDeckLike(home, item),
        onSelectSuggestion: (item) => controller.selectOnDeckLike(home, item),
        onHeroWatchTogether: (item) => controller.openWatchTogetherStart(
          ctx: emptyCtx(sectionGroupFor(home.sectionGroups, item.value.type)),
          server: item.server,
          returnState: home,
          roomTitle: _episodeRoomTitleFromOnDeck(item.value),
          thumb: item.value.thumb,
          targetRatingKey: item.value.ratingKey,
        ),
      ),
    );
  }

  String _episodeRoomTitleFromOnDeck(PlexOnDeckItem item) {
    final season = item.parentIndex;
    final ep = item.index;
    final show = item.grandparentTitle;
    if (show != null && season != null && ep != null) return '$show · S${season}E$ep';
    return item.title;
  }

  Widget _drawer({
    required LibraryContext ctx,
    required bool isHomeSelected,
    bool isSettingsSelected = false,
    bool isSearchSelected = false,
    required Widget child,
  }) {
    return AppNavigationDrawer(
      sectionGroups: ctx.sectionGroups,
      selectedSectionGroupKey: ctx.selectedSectionGroup.key,
      isSettingsSelected: isSettingsSelected,
      isHomeSelected: isHomeSelected,
      isSearchSelected: isSearchSelected,
      onSelectSection: (group) => controller.selectSection(ctx, group),
      onOpenSettings: () => controller.returnTo(Settings(ctx: ctx, returnState: Library(ctx: ctx))),
      onOpenHome: () => controller.goHome(ctx.servers, ctx.sectionGroups),
      onOpenSearch: () => controller.returnTo(Search(ctx: ctx, returnState: Library(ctx: ctx))),
      onOpenWatchlist: () => controller.returnTo(Watchlist(ctx: ctx)),
      account: controller.localAccount,
      versionName: _appVersionName,
      connectedServers: controller.connectedServers,
      disabledServerIds: controller.currentSettings.disabledServerIds,
      loadServers: _loadServers,
      probeServer: _probeServer,
      loadLibraryCount: _loadLibraryCount,
      onToggleServer: _toggleServer,
      child: child,
    );
  }

  void _toggleServer(PlexResource resource, bool enabled) =>
      controller.setServerEnabled(resource.machineIdentifier, enabled);

  Future<List<PlexResource>> _loadServers() => PlexResourcesApi(controller.clientIdentifier).listServers(controller.accountTokenOrEmpty);

  Future<ReachableServer?> _probeServer(PlexResource resource) => PlexResourcesApi(controller.clientIdentifier).connectToResource(resource);

  Future<int?> _loadLibraryCount(PlexServer server) async => (await PlexServerApi(server, controller.clientIdentifier).fetchSections()).length;

  /// Fans a search query out across every connected server concurrently —
  /// DESIGN.md screen 05 is explicitly "global across servers", grouped and
  /// labelled by which server each result came from — then folds duplicate
  /// works into one card, same as every other merge boundary.
  Future<List<FoldedWork<PlexOnDeckItem>>> _fanOutSearch(LibraryContext ctx, String query) async {
    final results = await Future.wait(ctx.servers.map((cs) async {
      try {
        final hits = await PlexServerApi(cs.server, controller.clientIdentifier).search(query);
        return hits.map((i) => Sourced(i, cs.server, cs.reachability)).toList();
      } catch (_) {
        return const <Sourced<PlexOnDeckItem>>[];
      }
    }));
    return foldByGuid(results.expand((l) => l).toList(), guidOf: (i) => i.guid);
  }

  /// Converts every copy of a [FoldedWork]&lt;PlexOnDeckItem&gt; through
  /// [convert] into a library-item-shaped [FoldedWork], preserving the
  /// fold's guid and copy set — mirrors the same-named private helper in
  /// app_root_controller.dart, duplicated here since that one is
  /// library-private.
  FoldedWork<PlexLibraryItem> _libraryWorkFrom(FoldedWork<PlexOnDeckItem> work, PlexLibraryItem Function(PlexOnDeckItem) convert) =>
      FoldedWork(work.guid, work.copies.map((c) => Sourced(convert(c.value), c.server, c.reachability)).toList());

  /// Same fan-out shape as items themselves (_fetchGroupItems in the
  /// controller) — collections aren't foldable works (no guid), so they're
  /// merged across servers but never deduplicated.
  Future<List<Sourced<PlexCollection>>> _fetchGroupCollections(LibraryContext ctx) async {
    final results = await Future.wait(ctx.servers.map((cs) async {
      final section = ctx.selectedSectionGroup.sectionOn(cs.server.machineIdentifier);
      if (section == null) return const <Sourced<PlexCollection>>[];
      try {
        final collections = await PlexServerApi(cs.server, controller.clientIdentifier).fetchCollections(section.key);
        return collections.map((c) => Sourced(c, cs.server, cs.reachability)).toList();
      } catch (_) {
        return const <Sourced<PlexCollection>>[];
      }
    }));
    return results.expand((l) => l).toList();
  }

  void _openCollection(LibraryContext ctx, Sourced<PlexCollection> collection) async {
    try {
      final items = await PlexServerApi(collection.server, controller.clientIdentifier).fetchCollectionItems(collection.value.ratingKey);
      controller.returnTo(CollectionDetail(ctx: ctx, collection: collection, items: items, returnState: Library(ctx: ctx)));
    } catch (_) {
      controller.returnTo(CollectionDetail(ctx: ctx, collection: collection, items: const [], returnState: Library(ctx: ctx)));
    }
  }

  String _episodeRoomTitle(PlexLibraryItem show, PlexEpisode episode) {
    final season = episode.parentIndex;
    final ep = episode.index;
    if (season != null && ep != null) return '${show.title} · S${season}E$ep';
    return show.title;
  }

  /// Looks a bare [PlexServer] (e.g. from a single-server drill-down state
  /// like [PersonFilmography]) back up in [ctx]'s connected-server list for
  /// its reachability, defaulting to [ServerReachability.local] if it's
  /// somehow no longer present — best-effort, since the server was already
  /// known reachable enough to have gotten this far.
  ServerReachability _reachabilityOf(LibraryContext ctx, PlexServer server) =>
      ctx.servers.firstWhereOrNull((s) => s.server.machineIdentifier == server.machineIdentifier)?.reachability ??
      ServerReachability.local;
}
