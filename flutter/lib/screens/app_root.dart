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
      PlaybackFailed(:final ctx, :final targetRatingKey, :final fromStart, :final reason, :final returnState) => PlaybackFailedScreen(
          reason: reason,
          onRetry: () => controller.playMovie(ctx, targetRatingKey, returnState, fromStart: fromStart),
          onBack: () => controller.returnTo(returnState),
        ),
      AppError(:final message, :final retryState) => BackHandler(
          onBack: () => controller.returnTo(retryState),
          child: ColoredBox(
            color: AppColors.background,
            child: Center(child: AppText('Error: $message', style: AppTypography.body)),
          ),
        ),
      RelaySetup(:final ctx) => RelaySetupScreen(onDone: () => controller.goHome(ctx.server, ctx.sections)),
      Home() => _buildHome(state),
      Library(:final ctx) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: LibraryScreen(
            server: ctx.server,
            selectedSection: ctx.selectedSection,
            items: ctx.items,
            onSelectItem: (item) => controller.returnTo(MovieDetail(ctx: ctx, movie: item, returnState: Library(ctx: ctx))),
            loadCollections: () async {
              try {
                return await _serverApi(ctx).fetchCollections(ctx.selectedSection.key);
              } catch (_) {
                return const [];
              }
            },
            onSelectCollection: (collection) => _openCollection(ctx, collection),
          ),
        ),
      LoadingSection(:final server, :final sections, :final selectedSectionKey, :final returnState) => BackHandler(
          onBack: () => controller.returnTo(returnState),
          child: AppNavigationDrawer(
            sections: sections,
            selectedSectionKey: selectedSectionKey,
            isSettingsSelected: false,
            isHomeSelected: false,
            onSelectSection: (_) {},
            onOpenSettings: () {},
            onOpenHome: () {},
            onOpenSearch: () {},
            account: controller.localAccount,
            versionName: _appVersionName,
            currentServer: server,
            loadServers: _loadServers,
            probeServer: _probeServer,
            loadLibraryCount: _loadLibraryCount,
            onSwitchServer: _switchServer,
            child: const LoadingScreen(),
          ),
        ),
      LoadingHome(:final server, :final sections) => AppNavigationDrawer(
          sections: sections,
          selectedSectionKey: null,
          isSettingsSelected: false,
          isHomeSelected: true,
          onSelectSection: (_) {},
          onOpenSettings: () {},
          onOpenHome: () {},
          onOpenSearch: () {},
          account: controller.localAccount,
          versionName: _appVersionName,
          currentServer: server,
          loadServers: _loadServers,
          probeServer: _probeServer,
          loadLibraryCount: _loadLibraryCount,
          onSwitchServer: _switchServer,
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
            server: ctx.server,
            search: (query) => _serverApi(ctx).search(query),
            onSelectResult: (item) => controller.returnTo(
              MovieDetail(
                ctx: ctx.copyWith(selectedSection: sectionFor(ctx.sections, item.type)),
                movie: libraryItemFrom(item),
                returnState: state,
              ),
            ),
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      Watchlist(:final ctx) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: WatchlistScreen(
            items: controller.watchlist,
            onSelectItem: (entry) => controller.openWatchlistItem(
              server: ctx.server,
              sections: ctx.sections,
              entry: entry,
              returnState: state,
            ),
            onRemove: controller.removeFromWatchlist,
          ),
        ),
      MovieDetail(:final ctx, :final movie, :final returnState) when ctx.selectedSection.type == _sectionTypeShow => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: ShowDetailScreen(
            server: ctx.server,
            show: movie,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            resolveNextEpisode: () async {
              try {
                return await _serverApi(ctx).fetchNextEpisodeForShow(movie.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadDetail: () async {
              try {
                return await _serverApi(ctx).fetchMovieDetail(movie.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadSeasons: () async {
              try {
                return await _serverApi(ctx).fetchSeasons(movie.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            loadEpisodes: (seasonRatingKey) async {
              try {
                return await _serverApi(ctx).fetchEpisodes(seasonRatingKey);
              } catch (_) {
                return const [];
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(ctx, targetRatingKey, state),
            onWatchTogether: (targetRatingKey) => controller.openWatchTogetherStart(
              ctx: ctx,
              returnState: state,
              roomTitle: movie.title,
              thumb: movie.thumb,
              targetRatingKey: targetRatingKey,
            ),
            onSelectEpisode: (episode) => controller.returnTo(EpisodeDetail(ctx: ctx, show: movie, episode: episode, returnState: state)),
          ),
        ),
      MovieDetail(:final ctx, :final movie, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: MovieDetailScreen(
            server: ctx.server,
            movie: movie,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadDetail: () async {
              try {
                return await _serverApi(ctx).fetchMovieDetail(movie.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadRelatedHubs: () async {
              try {
                return await _serverApi(ctx).fetchRelatedHubs(movie.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            loadByActor: (actorId) async {
              try {
                return await _serverApi(ctx).fetchLibraryItemsByActor(ctx.selectedSection.key, actorId);
              } catch (_) {
                return const [];
              }
            },
            onSelectRelated: (item) => controller.returnTo(
              MovieDetail(ctx: ctx, movie: libraryItemFrom(item), returnState: MovieDetail(ctx: ctx, movie: movie, returnState: returnState)),
            ),
            onSelectPerson: (person) async {
              final actorId = person.id;
              try {
                final items = actorId == null ? const <PlexLibraryItem>[] : await _serverApi(ctx).fetchLibraryItemsByActor(ctx.selectedSection.key, actorId);
                controller.returnTo(PersonFilmography(ctx: ctx, person: person, items: items, returnState: state));
              } catch (e) {
                controller.returnTo(AppError(message: '$e', retryState: state));
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(ctx, targetRatingKey, state),
            onWatchTogether: (targetRatingKey) => controller.openWatchTogetherStart(
              ctx: ctx,
              returnState: state,
              roomTitle: movie.title,
              thumb: movie.thumb,
              targetRatingKey: targetRatingKey,
            ),
            onRestartSolo: (targetRatingKey) => controller.playMovie(ctx, targetRatingKey, state, fromStart: true),
          ),
        ),
      PersonFilmography(:final ctx, :final person, :final items, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: PersonFilmographyScreen(
            server: ctx.server,
            personName: person.tag,
            personThumb: person.thumb,
            items: items,
            onSelectItem: (item) => controller.returnTo(MovieDetail(ctx: ctx, movie: item, returnState: state)),
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      CollectionDetail(:final ctx, :final collection, :final items, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: CollectionDetailScreen(
            server: ctx.server,
            collection: collection,
            items: items,
            onSelectItem: (item) => controller.returnTo(MovieDetail(ctx: ctx, movie: item, returnState: state)),
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      EpisodeDetail(:final ctx, :final show, :final episode, :final returnState) => _drawer(
          ctx: ctx,
          isHomeSelected: false,
          child: EpisodeDetailScreen(
            server: ctx.server,
            showTitle: show.title,
            episode: episode,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadShowGuid: () async {
              try {
                return (await _serverApi(ctx).fetchMovieDetail(show.ratingKey)).guid;
              } catch (_) {
                return null;
              }
            },
            onPlay: () => controller.playMovie(ctx, episode.ratingKey, state, showRatingKey: show.ratingKey),
            onPlayFromStart: () => controller.playMovie(ctx, episode.ratingKey, state, fromStart: true, showRatingKey: show.ratingKey),
            onWatchTogether: () => controller.openWatchTogetherStart(
              ctx: ctx,
              returnState: state,
              roomTitle: _episodeRoomTitle(show, episode),
              thumb: episode.thumb,
              targetRatingKey: episode.ratingKey,
            ),
            onRestartTogether: () => controller.openWatchTogetherStart(
              ctx: ctx,
              returnState: state,
              roomTitle: _episodeRoomTitle(show, episode),
              thumb: episode.thumb,
              targetRatingKey: episode.ratingKey,
              defaultRestart: true,
            ),
          ),
        ),
      WatchTogetherStart(:final ctx, :final returnState, :final roomTitle, :final thumb, :final targetRatingKey, :final defaultRestart) =>
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
              ? (next) => controller.playMovie(returnState.ctx, next.ratingKey, returnState, showRatingKey: showRatingKey)
              : null,
        ),
    };
  }

  Widget _buildHome(Home home) {
    return AppNavigationDrawer(
      sections: home.sections,
      isSettingsSelected: false,
      isHomeSelected: true,
      onSelectSection: (section) => controller.openSection(home.server, home.sections, section),
      onOpenSettings: () => controller.returnTo(Settings(
        ctx: LibraryContext(server: home.server, sections: home.sections, selectedSection: home.sections.first, items: const []),
        returnState: home,
      )),
      onOpenSearch: () => controller.returnTo(Search(
        ctx: LibraryContext(server: home.server, sections: home.sections, selectedSection: home.sections.first, items: const []),
        returnState: home,
      )),
      onOpenWatchlist: () => controller.returnTo(Watchlist(
        ctx: LibraryContext(server: home.server, sections: home.sections, selectedSection: home.sections.first, items: const []),
      )),
      // Clicking Home while already on Home used to be a pure no-op —
      // no state change at all means nothing ever reclaims focus from the
      // nav rail, so the drawer never collapses back down (it only
      // collapses on focus loss). Reloading Home, same as every other
      // sidebar item does even when re-selecting its own current screen,
      // gives HomeScreen a real remount and its existing autofocus does
      // the rest.
      onOpenHome: () => controller.goHome(home.server, home.sections),
      account: controller.localAccount,
      versionName: _appVersionName,
      currentServer: home.server,
      loadServers: _loadServers,
      probeServer: _probeServer,
      loadLibraryCount: _loadLibraryCount,
      onSwitchServer: _switchServer,
      child: HomeScreen(
        server: home.server,
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
          ctx: LibraryContext(server: home.server, sections: home.sections, selectedSection: sectionFor(home.sections, item.type), items: const []),
          returnState: home,
          roomTitle: _episodeRoomTitleFromOnDeck(item),
          thumb: item.thumb,
          targetRatingKey: item.ratingKey,
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
      sections: ctx.sections,
      selectedSectionKey: ctx.selectedSection.key,
      isSettingsSelected: isSettingsSelected,
      isHomeSelected: isHomeSelected,
      isSearchSelected: isSearchSelected,
      onSelectSection: (section) => controller.selectSection(ctx, section),
      onOpenSettings: () => controller.returnTo(Settings(ctx: ctx, returnState: Library(ctx: ctx))),
      onOpenHome: () => controller.goHome(ctx.server, ctx.sections),
      onOpenSearch: () => controller.returnTo(Search(ctx: ctx, returnState: Library(ctx: ctx))),
      onOpenWatchlist: () => controller.returnTo(Watchlist(ctx: ctx)),
      account: controller.localAccount,
      versionName: _appVersionName,
      currentServer: ctx.server,
      loadServers: _loadServers,
      probeServer: _probeServer,
      loadLibraryCount: _loadLibraryCount,
      onSwitchServer: _switchServer,
      child: child,
    );
  }

  void _switchServer(PlexResource resource) => controller.switchServer(resource.machineIdentifier);

  Future<List<PlexResource>> _loadServers() => PlexResourcesApi(controller.clientIdentifier).listServers(controller.accountTokenOrEmpty);

  Future<ReachableServer?> _probeServer(PlexResource resource) => PlexResourcesApi(controller.clientIdentifier).connectToResource(resource);

  Future<int?> _loadLibraryCount(PlexServer server) async => (await PlexServerApi(server, controller.clientIdentifier).fetchSections()).length;

  void _openCollection(LibraryContext ctx, PlexCollection collection) async {
    try {
      final items = await _serverApi(ctx).fetchCollectionItems(collection.ratingKey);
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

  /// Every LibraryContext-shaped state constructs its own `PlexServerApi` —
  /// matches MainActivity.kt, which does the same (no cached instance).
  PlexServerApi _serverApi(LibraryContext ctx) => PlexServerApi(ctx.server, controller.clientIdentifier);
}
