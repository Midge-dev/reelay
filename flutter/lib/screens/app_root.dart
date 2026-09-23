import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart';
import '../data/plex/plex_server_api.dart';
import '../focus/back_handler.dart';
import '../focus/screen_memory.dart';
import '../kit/text.dart';
import '../state/app_root_controller.dart';
import '../state/app_state.dart';
import '../state/data_providers.dart';
import '../state/duplicate_fold.dart';
import '../sync/relay_directory_api.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'onboarding/onboarding_screen.dart';
import 'onboarding/setup_ready_screen.dart';
import 'onboarding/watch_together_step.dart';
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
import 'settings/settings_screen.dart';
import 'splash/splash_screen.dart';

const _sectionTypeShow = 'show';
const _appVersionName = '0.3.0';

/// Renders whichever AppState is current, with the splash drawn over it on
/// cold start until the app underneath is ready (see [SplashScreen]).
/// Every screen and callback below is wired to [AppRootController] — see
/// that file for the actual business logic (each method there is a direct
/// port of one of MainActivity.kt's local closures).
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  /// Cold start only: this state lives for the process, so resuming from
  /// the background never shows the splash again.
  bool _showSplash = true;
  final _ready = Completer<void>();
  bool _startedOnce = false;
  // Screen 12 opens over whatever screen is showing, so its open state
  // outlives any one screen's drawer.
  final _roomsPanelOpen = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // Nothing hidden under the splash should react to the remote.
    HardwareKeyboard.instance.addHandler(_swallowKeysDuringSplash);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_swallowKeysDuringSplash);
    _roomsPanelOpen.dispose();
    super.dispose();
  }

  bool _swallowKeysDuringSplash(KeyEvent event) => _showSplash;

  void _start() {
    if (_startedOnce) return;
    _startedOnce = true;
    ref.read(appRootControllerProvider).start();
  }

  /// Splash spec: ready once startup has resolved to a real screen — Home
  /// with its rows, first-run setup, the no-servers screen. Checking and
  /// connecting are what the splash covers.
  void _noteReady(AppState state) {
    if (_ready.isCompleted) return;
    if (state is Checking || state is ConnectingToServer) return;
    _ready.complete();
  }

  void _splashDone() {
    HardwareKeyboard.instance.removeHandler(_swallowKeysDuringSplash);
    setState(() => _showSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appRootControllerProvider);

    // The app is built underneath from the first frame, so its data loads
    // during the intro and the exit reveals an already-painted screen.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: AppColors.background,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              _noteReady(controller.state);
              return _AppContent(
                controller: controller,
                roomsPanelOpen: _roomsPanelOpen,
              );
            },
          ),
        ),
        if (_showSplash)
          SplashScreen(ready: _ready.future, onDone: _splashDone),
      ],
    );
  }
}

/// Split out from [_AppRootState] so the splash-hold bookkeeping above
/// doesn't get lost in the size of the state switch below.
class _AppContent extends StatelessWidget {
  final AppRootController controller;
  final ValueNotifier<bool> roomsPanelOpen;

  const _AppContent({required this.controller, required this.roomsPanelOpen});

  /// The rail item a screen belongs to: its own for a rail destination,
  /// otherwise whichever destination it was opened from (a detail page
  /// reached from Home keeps Home lit, not the library its title lives in).
  static RailDestination _destinationFor(AppState state) => switch (state) {
    Home() || LoadingHome() => RailDestination.home,
    Library() || LoadingSection() => RailDestination.section,
    Search() => RailDestination.search,
    Watchlist() => RailDestination.watchlist,
    Settings() => RailDestination.settings,
    MovieDetail(:final returnState) ||
    PersonFilmography(:final returnState) ||
    CollectionDetail(:final returnState) ||
    EpisodeDetail(:final returnState) ||
    WatchTogetherStart(:final returnState) => _destinationFor(returnState),
    PlaybackFailed(:final returnState) => _destinationFor(returnState),
    _ => RailDestination.none,
  };

  RoomsPanelData _roomsData(AppState current, List<ReachableServer> servers) =>
      RoomsPanelData(
        relays: controller.liveRelays,
        relayHealth: controller.relayHealth,
        rooms: controller.liveRooms,
        myRoomId: controller.myRoomId,
        hostedRoomIds: controller.hostedRoomIds,
        onJoin: (room) => controller.joinRoom(current, servers, room),
        onRetry: controller.retryRelays,
      );

  @override
  Widget build(BuildContext context) => _screenFor(context, controller.state);

  /// The screen for [state]. Also used to draw the page a dialog state was
  /// opened from underneath it (screen 09).
  Widget _screenFor(BuildContext context, AppState state) {
    return switch (state) {
      Checking() => const LoadingScreen(),
      ConnectingToServer(
        :final firstRun,
        :final done,
        :final current,
        :final headline,
      )
          when firstRun =>
        SetupReadyScreen(done: done, current: current, headline: headline),
      ConnectingToServer(:final username) => LoadingScreen(
        username != null
            ? 'Logged in as $username — connecting to library…'
            : 'Connecting to library…',
      ),
      LoggedOut() => OnboardingScreen(
        onComplete: controller.completeFirstLogin,
      ),
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
      PlaybackFailed(
        :final ctx,
        :final server,
        :final targetRatingKey,
        :final fromStart,
        :final reason,
        :final returnState,
      ) =>
        Stack(
          fit: StackFit.expand,
          children: [
            // Screen 25: the dialog stays over the detail page, so nothing is
            // lost — same inert-page-underneath treatment as screen 09.
            ExcludeFocus(
              child: IgnorePointer(child: _screenFor(context, returnState)),
            ),
            BackHandler(
              onBack: () => controller.returnTo(returnState),
              child: PlaybackFailedScreen(
                reason: reason,
                serverName: server.name,
                onRetry: () => controller.playMovie(
                  ctx,
                  server,
                  targetRatingKey,
                  returnState,
                  fromStart: fromStart,
                ),
                alternateServerName: _alternateSourceFor(
                  returnState,
                  server,
                )?.server.name,
                onPlayAlternate:
                    _alternateSourceFor(returnState, server) == null
                    ? null
                    : () {
                        final alternate = _alternateSourceFor(
                          returnState,
                          server,
                        )!;
                        controller.playMovie(
                          ctx,
                          alternate.server,
                          alternate.value.ratingKey,
                          returnState,
                          fromStart: fromStart,
                        );
                      },
                onBack: () => controller.returnTo(returnState),
              ),
            ),
          ],
        ),
      AppError(:final message, :final retryState) => BackHandler(
        onBack: () => controller.returnTo(retryState),
        child: ColoredBox(
          color: AppColors.background,
          child: Center(
            child: AppText('Error: $message', style: AppTypography.body),
          ),
        ),
      ),
      // An install set up before the Watch Together step existed meets it
      // once, framed as the setup step it is.
      RelaySetup(:final ctx) => WatchTogetherStep(
        onDone: () => controller.goHome(ctx.servers, ctx.sectionGroups),
      ),
      Home() => _buildHome(state),
      Library(:final ctx, :final returnState) => BackHandler(
        onBack: () => controller.returnTo(returnState),
        child: _drawer(
          state: state,
          ctx: ctx,
          child: LibraryScreen(
            servers: ctx.servers,
            selectedSectionGroup: ctx.selectedSectionGroup,
            items: ctx.items,
            onSelectItem: (item) => controller.returnTo(
              MovieDetail(
                ctx: ctx,
                work: item,
                activeCopy: item.primary,
                returnState: state,
              ),
            ),
            loadCollections: () => _fetchGroupCollections(ctx),
            onSelectCollection: (collection) =>
                _openCollection(ctx, collection, state),
          ),
        ),
      ),
      LoadingSection(
        :final sectionGroups,
        :final selectedSectionGroupKey,
        :final returnState,
      ) =>
        BackHandler(
          onBack: () => controller.returnTo(returnState),
          child: AppNavigationDrawer(
            sectionGroups: sectionGroups,
            selectedSectionGroupKey: selectedSectionGroupKey,
            destination: RailDestination.section,
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
        destination: RailDestination.home,
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
        state: state,
        ctx: ctx,
        child: SettingsScreen(
          accountToken: controller.accountTokenOrEmpty,
          clientIdentifier: controller.clientIdentifier,
          hint: relayHint,
          versionName: _appVersionName,
          onBack: () => controller.returnTo(returnState),
          onServersChanged: () {
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
        state: state,
        ctx: ctx,
        child: SearchScreen(
          servers: ctx.servers,
          search: (query) => _fanOutSearch(ctx, query),
          onSelectResult: (item) {
            final work = _libraryWorkFrom(item, libraryItemFrom);
            controller.returnTo(
              MovieDetail(
                ctx: ctx.copyWith(
                  selectedSectionGroup: sectionGroupFor(
                    ctx.sectionGroups,
                    work.primary.value.type ?? '',
                  ),
                ),
                work: work,
                activeCopy: work.primary,
                returnState: state,
              ),
            );
          },
          onBack: () => controller.returnTo(returnState),
        ),
      ),
      Watchlist(:final ctx, :final returnState) => BackHandler(
        onBack: () => controller.returnTo(returnState),
        child: _drawer(
          state: state,
          ctx: ctx,
          child: WatchlistScreen(
            items: controller.watchlist,
            onSelectItem: (entry) => controller.openWatchlistItem(
              servers: ctx.servers,
              sectionGroups: ctx.sectionGroups,
              entry: entry,
              returnState: state,
            ),
            onRemove: controller.removeFromWatchlist,
            accountName: controller.localAccount?.username,
            availability: controller.watchlistAvailability,
          ),
        ),
      ),
      MovieDetail(
        :final ctx,
        :final work,
        :final activeCopy,
        :final returnState,
      )
          when ctx.selectedSectionGroup.type == _sectionTypeShow =>
        _drawer(
          state: state,
          ctx: ctx,
          child: ShowDetailScreen(
            server: activeCopy.server,
            show: activeCopy.value,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            resolveNextEpisode: () async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchNextEpisodeForShow(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadDetail: () async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchMovieDetail(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadSeasons: () async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchSeasons(activeCopy.value.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            loadEpisodes: (seasonRatingKey) async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchEpisodes(seasonRatingKey);
              } catch (_) {
                return const [];
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(
              ctx,
              activeCopy.server,
              targetRatingKey,
              state,
            ),
            onWatchTogether: (targetRatingKey) =>
                controller.openWatchTogetherStart(
                  ctx: ctx,
                  server: activeCopy.server,
                  returnState: state,
                  roomTitle: activeCopy.value.title,
                  thumb: activeCopy.value.thumb,
                  targetRatingKey: targetRatingKey,
                ),
            onSelectEpisode: (episode) => controller.returnTo(
              EpisodeDetail(
                ctx: ctx,
                work: work,
                activeCopy: activeCopy,
                episode: episode,
                returnState: state,
              ),
            ),
          ),
        ),
      MovieDetail(
        :final ctx,
        :final work,
        :final activeCopy,
        :final returnState,
      ) =>
        _drawer(
          state: state,
          ctx: ctx,
          child: MovieDetailScreen(
            server: activeCopy.server,
            movie: activeCopy.value,
            work: work,
            onSwitchSource: (copy) => controller.returnTo(
              MovieDetail(
                ctx: ctx,
                work: work,
                activeCopy: copy,
                returnState: returnState,
              ),
            ),
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadDetail: () async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchMovieDetail(activeCopy.value.ratingKey);
              } catch (_) {
                return null;
              }
            },
            loadRelatedHubs: () async {
              try {
                return await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchRelatedHubs(activeCopy.value.ratingKey);
              } catch (_) {
                return const [];
              }
            },
            onSelectRelated: (item) {
              final newWork = FoldedWork<PlexLibraryItem>(item.guid, [
                Sourced(
                  libraryItemFrom(item),
                  activeCopy.server,
                  activeCopy.reachability,
                ),
              ]);
              controller.returnTo(
                MovieDetail(
                  ctx: ctx,
                  work: newWork,
                  activeCopy: newWork.primary,
                  returnState: MovieDetail(
                    ctx: ctx,
                    work: work,
                    activeCopy: activeCopy,
                    returnState: returnState,
                  ),
                ),
              );
            },
            onSelectPerson: (person) async {
              final actorId = person.id;
              final section = ctx.selectedSectionGroup.sectionOn(
                activeCopy.server.machineIdentifier,
              );
              try {
                final items = actorId == null || section == null
                    ? const <PlexLibraryItem>[]
                    : await PlexServerApi(
                        activeCopy.server,
                        controller.clientIdentifier,
                      ).fetchLibraryItemsByActor(section.key, actorId);
                controller.returnTo(
                  PersonFilmography(
                    ctx: ctx,
                    server: activeCopy.server,
                    person: person,
                    items: items,
                    returnState: state,
                  ),
                );
              } catch (e) {
                controller.returnTo(AppError(message: '$e', retryState: state));
              }
            },
            onPlay: (targetRatingKey) => controller.playMovie(
              ctx,
              activeCopy.server,
              targetRatingKey,
              state,
            ),
            onWatchTogether: (targetRatingKey) =>
                controller.openWatchTogetherStart(
                  ctx: ctx,
                  server: activeCopy.server,
                  returnState: state,
                  roomTitle: activeCopy.value.title,
                  thumb: activeCopy.value.thumb,
                  targetRatingKey: targetRatingKey,
                ),
            onRestartSolo: (targetRatingKey) => controller.playMovie(
              ctx,
              activeCopy.server,
              targetRatingKey,
              state,
              fromStart: true,
            ),
          ),
        ),
      PersonFilmography(
        :final ctx,
        :final server,
        :final person,
        :final items,
        :final returnState,
      ) =>
        _drawer(
          state: state,
          ctx: ctx,
          child: PersonFilmographyScreen(
            server: server,
            personName: person.tag,
            personThumb: person.thumb,
            items: items,
            onSelectItem: (item) {
              final work = FoldedWork<PlexLibraryItem>(item.guid, [
                Sourced(item, server, _reachabilityOf(ctx, server)),
              ]);
              controller.returnTo(
                MovieDetail(
                  ctx: ctx,
                  work: work,
                  activeCopy: work.primary,
                  returnState: state,
                ),
              );
            },
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      CollectionDetail(
        :final ctx,
        :final collection,
        :final items,
        :final returnState,
      ) =>
        _drawer(
          state: state,
          ctx: ctx,
          child: CollectionDetailScreen(
            server: collection.server,
            collection: collection.value,
            items: items,
            onSelectItem: (item) {
              final work = FoldedWork<PlexLibraryItem>(item.guid, [
                Sourced(item, collection.server, collection.reachability),
              ]);
              controller.returnTo(
                MovieDetail(
                  ctx: ctx,
                  work: work,
                  activeCopy: work.primary,
                  returnState: state,
                ),
              );
            },
            onBack: () => controller.returnTo(returnState),
          ),
        ),
      EpisodeDetail(
        :final ctx,
        :final activeCopy,
        :final episode,
        :final returnState,
      ) =>
        _drawer(
          state: state,
          ctx: ctx,
          child: EpisodeDetailScreen(
            server: activeCopy.server,
            showTitle: activeCopy.value.title,
            episode: episode,
            onBack: () => controller.returnTo(returnState),
            isOnWatchlist: controller.isOnWatchlist,
            onToggleWatchlist: controller.toggleWatchlist,
            loadShowGuid: () async {
              try {
                return (await PlexServerApi(
                  activeCopy.server,
                  controller.clientIdentifier,
                ).fetchMovieDetail(activeCopy.value.ratingKey)).guid;
              } catch (_) {
                return null;
              }
            },
            onPlay: () => controller.playMovie(
              ctx,
              activeCopy.server,
              episode.ratingKey,
              state,
              showRatingKey: activeCopy.value.ratingKey,
            ),
            onPlayFromStart: () => controller.playMovie(
              ctx,
              activeCopy.server,
              episode.ratingKey,
              state,
              fromStart: true,
              showRatingKey: activeCopy.value.ratingKey,
            ),
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
      // BackHandler: without it Back fell through to Android and closed
      // the app instead of cancelling the dialog.
      WatchTogetherStart(
        :final ctx,
        :final server,
        :final returnState,
        :final roomTitle,
        :final thumb,
        :final targetRatingKey,
        :final defaultRestart,
      ) =>
        Stack(
          fit: StackFit.expand,
          children: [
            // Screen 09: a dialog over the page it was opened from, so the
            // feature stays attached to what you are watching. The page is
            // drawn but inert — no focus, no pointer.
            ExcludeFocus(
              child: IgnorePointer(child: _screenFor(context, returnState)),
            ),
            BackHandler(
              onBack: () => controller.returnTo(returnState),
              child: WatchTogetherStartScreen(
                roomTitle: roomTitle,
                defaultRestart: defaultRestart,
                maxSeats: controller.currentSettings.maxHostSeats,
                relayNickname:
                    controller.currentSettings.defaultRelay?.nickname,
                checkRelayReachable:
                    controller.currentSettings.defaultRelay == null
                    ? null
                    : () => RelayDirectoryApi().testReachable(
                        controller.currentSettings.defaultRelay!.url,
                      ),
                onConfirm: ({required restart, required showPhoneChat}) =>
                    controller.startWatchTogether(
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
            ),
          ],
        ),
      Lobby(
        :final detail,
        :final returnState,
        :final relay,
        :final hostName,
        :final relayNickname,
        :final isHost,
      ) =>
        LobbyScreen(
          key: ValueKey('lobby-${detail.ratingKey}'),
          server: state.server,
          detail: detail,
          localUsername: controller.localAccount?.username ?? 'You',
          localAvatarUrl: controller.localAccount?.thumb,
          hostName: hostName,
          relayNickname: relayNickname,
          measureLatency: () => controller.measureRelayLatency(relay.relayUrl),
          relay: relay,
          onHostOnAnother: isHost
              ? () => controller.hostOnAnotherRelay(state)
              : null,
          onStart: (restartFromBeginning) => controller.returnTo(
            Player(
              server: state.server,
              detail: restartFromBeginning
                  ? detail.copyWith(viewOffset: 0)
                  : detail,
              returnState: returnState,
              relay: relay,
            ),
          ),
          onBack: () {
            controller.releaseRelayClient();
            controller.returnTo(returnState);
          },
        ),
      Player(
        :final detail,
        :final returnState,
        :final relay,
        :final showRatingKey,
      ) =>
        PlayerScreen(
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
              : () => PlexServerApi(
                  state.server,
                  controller.clientIdentifier,
                ).fetchNextEpisodeForShow(showRatingKey),
          onPlayNext: returnState is EpisodeDetail
              ? (next) => controller.playMovie(
                  returnState.ctx,
                  state.server,
                  next.ratingKey,
                  returnState,
                  showRatingKey: showRatingKey,
                )
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
      destination: RailDestination.home,
      rooms: _roomsData(home, home.servers),
      roomsPanelOpen: roomsPanelOpen,
      onSelectSection: (group) =>
          controller.openSection(home.servers, home.sectionGroups, group),
      onOpenSettings: () => controller.returnTo(
        Settings(ctx: emptyCtx(home.sectionGroups.first), returnState: home),
      ),
      onOpenSearch: () => controller.returnTo(
        Search(ctx: emptyCtx(home.sectionGroups.first), returnState: home),
      ),
      onOpenWatchlist: () => controller.returnTo(
        Watchlist(ctx: emptyCtx(home.sectionGroups.first), returnState: home),
      ),
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
      child: _remembering(
        home,
        HomeScreen(
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
          onSelectRoom: (merged) =>
              controller.joinRoom(home, home.servers, merged),
          onOpenRooms: () => roomsPanelOpen.value = true,
          onResume: (item) => controller.resumeOnDeckItem(home, item),
          onRemove: (item) => controller.removeFromContinueWatching(home, item),
          onSelectWatchlistItem: (entry) =>
              controller.selectWatchlistItem(home, entry),
          onRemoveFromWatchlist: controller.removeFromWatchlist,
          onSelectRecentlyAdded: (item) =>
              controller.selectRecentlyAdded(home, item),
          onSelectRecentActivity: (item) =>
              controller.selectOnDeckLike(home, item),
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
      ),
    );
  }

  String _episodeRoomTitleFromOnDeck(PlexOnDeckItem item) {
    final season = item.parentIndex;
    final ep = item.index;
    final show = item.grandparentTitle;
    if (show != null && season != null && ep != null)
      return '$show · S${season}E$ep';
    return item.title;
  }

  /// [state] is the screen being drawn — not necessarily
  /// `controller.state`, which is the dialog when this is the page drawn
  /// underneath one.
  Widget _drawer({
    required AppState state,
    required LibraryContext ctx,
    required Widget child,
  }) {
    return AppNavigationDrawer(
      sectionGroups: ctx.sectionGroups,
      selectedSectionGroupKey: ctx.selectedSectionGroup.key,
      destination: _destinationFor(state),
      rooms: _roomsData(state, ctx.servers),
      roomsPanelOpen: roomsPanelOpen,
      onSelectSection: (group) => controller.selectSection(ctx, group),
      // Back from a rail destination returns to the screen it was opened
      // from — not a made-up Library, which is what these used to return
      // to even from a detail page or Search.
      onOpenSettings: () =>
          controller.returnTo(Settings(ctx: ctx, returnState: state)),
      onOpenHome: () => controller.goHome(ctx.servers, ctx.sectionGroups),
      onOpenSearch: () =>
          controller.returnTo(Search(ctx: ctx, returnState: state)),
      onOpenWatchlist: () =>
          controller.returnTo(Watchlist(ctx: ctx, returnState: state)),
      account: controller.localAccount,
      versionName: _appVersionName,
      connectedServers: controller.connectedServers,
      disabledServerIds: controller.currentSettings.disabledServerIds,
      loadServers: _loadServers,
      probeServer: _probeServer,
      loadLibraryCount: _loadLibraryCount,
      onToggleServer: _toggleServer,
      child: _remembering(state, child),
    );
  }

  /// Back hands a screen its own AppState object again; this gives the
  /// screen that object's [ScreenMemory], so it comes back as it was left.
  static Widget _remembering(AppState state, Widget screen) {
    final memory = ScreenMemory.of(state);
    return ScreenMemoryScope(
      key: ObjectKey(memory),
      memory: memory,
      child: screen,
    );
  }

  void _toggleServer(PlexResource resource, bool enabled) =>
      controller.setServerEnabled(resource.machineIdentifier, enabled);

  Future<List<PlexResource>> _loadServers() =>
      PlexResourcesApi(controller.clientIdentifier)
          .listServers(controller.accountTokenOrEmpty);

  Future<ReachableServer?> _probeServer(PlexResource resource) =>
      PlexResourcesApi(controller.clientIdentifier).connectToResource(resource);

  Future<int?> _loadLibraryCount(PlexServer server) async =>
      (await PlexServerApi(
        server,
        controller.clientIdentifier,
      ).fetchSections()).length;

  /// Fans a search query out across every connected server concurrently —
  /// DESIGN.md screen 05 is explicitly "global across servers", grouped and
  /// labelled by which server each result came from — then folds duplicate
  /// works into one card, same as every other merge boundary.
  Future<List<FoldedWork<PlexOnDeckItem>>> _fanOutSearch(
    LibraryContext ctx,
    String query,
  ) async {
    final results = await Future.wait(
      ctx.servers.map((cs) async {
        try {
          final hits = await PlexServerApi(
            cs.server,
            controller.clientIdentifier,
          ).search(query);
          return hits
              .map((i) => Sourced(i, cs.server, cs.reachability))
              .toList();
        } catch (_) {
          return const <Sourced<PlexOnDeckItem>>[];
        }
      }),
    );
    return foldByGuid(
      results.expand((l) => l).toList(),
      guidOf: (i) => i.guid,
      alternateIdsOf: (i) => i.guids.map((g) => g.id).toList(),
    );
  }

  /// Converts every copy of a [FoldedWork]&lt;PlexOnDeckItem&gt; through
  /// [convert] into a library-item-shaped [FoldedWork], preserving the
  /// fold's guid and copy set — mirrors the same-named private helper in
  /// app_root_controller.dart, duplicated here since that one is
  /// library-private.
  FoldedWork<PlexLibraryItem> _libraryWorkFrom(
    FoldedWork<PlexOnDeckItem> work,
    PlexLibraryItem Function(PlexOnDeckItem) convert,
  ) => FoldedWork(
    work.guid,
    work.copies
        .map((c) => Sourced(convert(c.value), c.server, c.reachability))
        .toList(),
  );

  /// Same fan-out shape as items themselves (_fetchGroupItems in the
  /// controller) — collections aren't foldable works (no guid), so they're
  /// merged across servers but never deduplicated.
  Future<List<Sourced<PlexCollection>>> _fetchGroupCollections(
    LibraryContext ctx,
  ) async {
    final results = await Future.wait(
      ctx.servers.map((cs) async {
        final section = ctx.selectedSectionGroup.sectionOn(
          cs.server.machineIdentifier,
        );
        if (section == null) return const <Sourced<PlexCollection>>[];
        try {
          final collections = await PlexServerApi(
            cs.server,
            controller.clientIdentifier,
          ).fetchCollections(section.key);
          return collections
              .map((c) => Sourced(c, cs.server, cs.reachability))
              .toList();
        } catch (_) {
          return const <Sourced<PlexCollection>>[];
        }
      }),
    );
    return results.expand((l) => l).toList();
  }

  void _openCollection(
    LibraryContext ctx,
    Sourced<PlexCollection> collection,
    AppState returnState,
  ) async {
    try {
      final items = await PlexServerApi(
        collection.server,
        controller.clientIdentifier,
      ).fetchCollectionItems(collection.value.ratingKey);
      controller.returnTo(
        CollectionDetail(
          ctx: ctx,
          collection: collection,
          items: items,
          returnState: returnState,
        ),
      );
    } catch (_) {
      controller.returnTo(
        CollectionDetail(
          ctx: ctx,
          collection: collection,
          items: const [],
          returnState: returnState,
        ),
      );
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
      ctx.servers
          .firstWhereOrNull(
            (s) => s.server.machineIdentifier == server.machineIdentifier,
          )
          ?.reachability ??
      ServerReachability.local;

  /// Screen 25's "Play from Loft" offer — the next reachable copy of the
  /// same work, excluding whichever server just failed. Only movies carry
  /// a [FoldedWork] wide enough to answer this today (an episode's alternate
  /// copy would need that episode's ratingKey re-resolved on the other
  /// server, which nothing here has fetched — see PlaybackFailed's own doc
  /// comment on why this is wired at the call site, not stored on the
  /// state, so this scope limit stays a local decision rather than a
  /// structural one).
  Sourced<PlexLibraryItem>? _alternateSourceFor(
    AppState returnState,
    PlexServer failedServer,
  ) {
    if (returnState is! MovieDetail) return null;
    return returnState.work.copies.firstWhereOrNull(
      (c) =>
          c.reachability != ServerReachability.unreachable &&
          c.server.machineIdentifier != failedServer.machineIdentifier,
    );
  }
}
