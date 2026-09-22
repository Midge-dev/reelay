import '../data/plex/plex_models.dart';
import '../data/plex/plex_resources_api.dart';
import '../data/settings/app_settings.dart';
import '../sync/relay_client.dart';
import 'duplicate_fold.dart';

/// One rail-level library destination (e.g. "Movies"). May be backed by the
/// same-named, same-typed [PlexSection] on more than one connected server —
/// the hub merges "Movies" on server A with "Movies" on server B into one
/// rail entry — but keeps differently-named libraries of the same type
/// separate (a server's "Home Videos" library stays its own rail entry
/// rather than folding into "Movies"), since those are organizationally
/// distinct to whoever set the server up that way, not duplicates of the
/// same content. Keyed on (type, title), not type alone.
class SectionGroup {
  final String type;
  final String title;

  /// The physical [PlexSection] this group resolves to on each server that
  /// has one — keyed by [PlexServer.machineIdentifier]. A server absent
  /// from this map simply has no matching library, not an error.
  final Map<String, PlexSection> sectionsByServerId;

  const SectionGroup({required this.type, required this.title, required this.sectionsByServerId});

  String get key => '$type::${title.toLowerCase()}';

  PlexSection? sectionOn(String machineIdentifier) => sectionsByServerId[machineIdentifier];
}

/// Unions same-(type,title) [PlexSection]s across every connected server
/// into rail-level [SectionGroup]s — see its own doc comment for why
/// (type, title), not type alone. [sectionsByServerId] is keyed by
/// [PlexServer.machineIdentifier]; a server with no sections fetched yet
/// (or none at all) is simply absent from every group.
List<SectionGroup> groupSections(Map<String, List<PlexSection>> sectionsByServerId) {
  final groups = <String, SectionGroup>{};
  final order = <String>[];
  for (final entry in sectionsByServerId.entries) {
    for (final section in entry.value) {
      final key = '${section.type}::${section.title.toLowerCase()}';
      final existing = groups[key];
      if (existing == null) {
        groups[key] = SectionGroup(type: section.type, title: section.title, sectionsByServerId: {entry.key: section});
        order.add(key);
      } else {
        groups[key] = SectionGroup(
          type: existing.type,
          title: existing.title,
          sectionsByServerId: {...existing.sectionsByServerId, entry.key: section},
        );
      }
    }
  }
  return [for (final k in order) groups[k]!];
}

/// Ports MainActivity.kt's private `LibraryContext` data class — the
/// servers/sections/selected-section/items bundle threaded through every
/// library-adjacent AppState. Widened for the multi-server hub: [servers]
/// is every connected server (not one), [sectionGroups]/[selectedSectionGroup]
/// union same-named libraries across them (see [SectionGroup]), and [items]
/// pairs each result with the server it came from — merged across servers,
/// not yet folded into one card per work (that's [FoldedWork], applied at
/// the screens that render these lists, not stored here).
class LibraryContext {
  final List<ReachableServer> servers;
  final List<SectionGroup> sectionGroups;
  final SectionGroup selectedSectionGroup;
  final List<Sourced<PlexLibraryItem>> items;

  const LibraryContext({
    required this.servers,
    required this.sectionGroups,
    required this.selectedSectionGroup,
    required this.items,
  });

  LibraryContext copyWith({SectionGroup? selectedSectionGroup, List<Sourced<PlexLibraryItem>>? items}) => LibraryContext(
        servers: servers,
        sectionGroups: sectionGroups,
        selectedSectionGroup: selectedSectionGroup ?? this.selectedSectionGroup,
        items: items ?? this.items,
      );
}

/// Ports MainActivity.kt's `sealed interface AppState` (the Kotlin app has
/// no Jetpack Navigation / nav-graph — one hand-rolled sealed state drives
/// a single `when`/switch). `returnState` mirrors the Kotlin back-stack
/// pattern: back navigation restores the captured state and re-fetches
/// fresh data for it, rather than using a URL-based router.
sealed class AppState {
  const AppState();
}

class Checking extends AppState {
  const Checking();
}

class LoggedOut extends AppState {
  const LoggedOut();
}

/// Screen 07 — shown only when 2+ profiles exist on the device (a
/// single-person household never sees it, per DESIGN.md). Never reachable
/// mid-session in this pass; only at cold start, matching the handoff's
/// "first screen after launch" framing.
class ProfilePicker extends AppState {
  final List<Profile> profiles;

  const ProfilePicker({required this.profiles});
}

class ConnectingToServer extends AppState {
  final String? username;

  const ConnectingToServer({this.username});
}

/// Kotlin's `Error` state has no way back at all (just a bare `Text`, no
/// BackHandler) — a genuine dead end there. This port adds [retryState] so
/// AppRoot can wire a back action, since every other screen in this app
/// supports back and a true dead end would be a jarring regression, not a
/// deliberate design choice worth preserving.
class AppError extends AppState {
  final String message;
  final AppState retryState;

  const AppError({required this.message, required this.retryState});
}

/// Screen 25 — a title that wouldn't start. Spec puts this as a dialog
/// over the (dimmed, still-visible) detail page; this port renders it as
/// its own full screen instead, matching how AppError already works here
/// rather than adding a new "render one AppState behind another" pattern
/// to app_root.dart for a single call site — a disclosed simplification,
/// not an oversight. [ctx]/[targetRatingKey]/[fromStart] are exactly
/// playMovie's own params, so retry is the identical call; an
/// alternate-source retry (screen 25's "Play from Loft" offer) is
/// possible now that [FoldedWork] exists, wired at the call site rather
/// than stored here.
class PlaybackFailed extends AppState {
  final LibraryContext ctx;
  final PlexServer server;
  final String targetRatingKey;
  final bool fromStart;
  final String reason;
  final AppState returnState;

  const PlaybackFailed({
    required this.ctx,
    required this.server,
    required this.targetRatingKey,
    required this.fromStart,
    required this.reason,
    required this.returnState,
  });
}

/// Screen 24 — the one failure that earns the whole screen, since with
/// every server gone (or deliberately disabled — see setServerEnabled)
/// there's no content behind it to keep visible. [resources] is the
/// account's full resource list, so the screen can name what actually
/// failed, not just say "something went wrong".
class NoServersReachable extends AppState {
  final String token;
  final List<PlexResource> resources;

  const NoServersReachable({required this.token, required this.resources});
}

class RelaySetup extends AppState {
  final LibraryContext ctx;

  const RelaySetup({required this.ctx});
}

class Home extends AppState {
  final List<ReachableServer> servers;
  final List<SectionGroup> sectionGroups;
  final List<Sourced<PlexOnDeckItem>> onDeck;
  final List<Sourced<PlexLibraryItem>> recentlyAdded;
  final List<Sourced<PlexOnDeckItem>> recentActivity;
  final List<Sourced<PlexOnDeckItem>> suggestions;
  // "Partial is not empty" (DESIGN.md) — servers that didn't answer at
  // connect time, named in a header line rather than treated as an error.
  final List<PlexResource> unreachableResources;

  const Home({
    required this.servers,
    required this.sectionGroups,
    required this.onDeck,
    required this.recentlyAdded,
    required this.recentActivity,
    required this.suggestions,
    this.unreachableResources = const [],
  });

  Home copyWith({List<Sourced<PlexOnDeckItem>>? onDeck}) => Home(
        servers: servers,
        sectionGroups: sectionGroups,
        onDeck: onDeck ?? this.onDeck,
        recentlyAdded: recentlyAdded,
        recentActivity: recentActivity,
        suggestions: suggestions,
        unreachableResources: unreachableResources,
      );
}

class Library extends AppState {
  final LibraryContext ctx;

  const Library({required this.ctx});
}

class LoadingSection extends AppState {
  final List<ReachableServer> servers;
  final List<SectionGroup> sectionGroups;
  final String? selectedSectionGroupKey;
  final AppState returnState;

  const LoadingSection({
    required this.servers,
    required this.sectionGroups,
    this.selectedSectionGroupKey,
    required this.returnState,
  });
}

/// Shown while `goHome`'s fetches are in flight — mirrors [LoadingSection],
/// which Home previously had no equivalent of: `goHome` used to hold on a
/// single `_setState` until every fetch resolved, so re-selecting Home from
/// the nav drawer showed nothing changing (and kept the drawer visually
/// expanded, since nothing became focusable to pull focus off the rail).
class LoadingHome extends AppState {
  final List<ReachableServer> servers;
  final List<SectionGroup> sectionGroups;

  const LoadingHome({required this.servers, required this.sectionGroups});
}

class Settings extends AppState {
  final LibraryContext ctx;
  final AppState returnState;
  final String? relayHint;

  const Settings({required this.ctx, required this.returnState, this.relayHint});
}

/// Rail-level and reachable from anywhere — DESIGN.md screen 05.
class Search extends AppState {
  final LibraryContext ctx;
  final AppState returnState;

  const Search({required this.ctx, required this.returnState});
}

/// Screen 20 — a rail-level peer destination like Library, not reached via
/// a back-stack (same shape as Library: no returnState). It "belongs to
/// the Plex account rather than to a server, so it spans every library at
/// once" (screen 20's own note) — [ctx] is only used for its
/// servers/sections, to resolve a tapped item the same way Home's existing
/// `selectWatchlistItem` already did; selectedSectionGroup/items are
/// irrelevant here.
class Watchlist extends AppState {
  final LibraryContext ctx;

  const Watchlist({required this.ctx});
}

class MovieDetail extends AppState {
  final LibraryContext ctx;
  final Sourced<PlexLibraryItem> movie;
  final AppState returnState;

  const MovieDetail({required this.ctx, required this.movie, required this.returnState});
}

/// [server] is whichever server [person] (and the movie/show they were
/// found on) actually came from — an actor's ratingKey is only meaningful
/// on the one server it was resolved against, so this drill-down stays
/// single-server rather than fanning out across the hub (v1 scope: the
/// hub unifies Home/Library/Search/Watchlist; a detail page's own
/// neighborhood — cast, collections, related — stays scoped to whichever
/// copy you're actually looking at, same simplification as episodes).
class PersonFilmography extends AppState {
  final LibraryContext ctx;
  final PlexServer server;
  final PlexPerson person;
  final List<PlexLibraryItem> items;
  final AppState returnState;

  const PersonFilmography({
    required this.ctx,
    required this.server,
    required this.person,
    required this.items,
    required this.returnState,
  });
}

class CollectionDetail extends AppState {
  final LibraryContext ctx;
  final Sourced<PlexCollection> collection;
  final List<PlexLibraryItem> items;
  final AppState returnState;

  const CollectionDetail({required this.ctx, required this.collection, required this.items, required this.returnState});
}

/// [episode] is fetched from [show]'s own server — same single-server
/// simplification as [PersonFilmography] (see its doc comment).
class EpisodeDetail extends AppState {
  final LibraryContext ctx;
  final Sourced<PlexLibraryItem> show;
  final PlexEpisode episode;
  final AppState returnState;

  const EpisodeDetail({required this.ctx, required this.show, required this.episode, required this.returnState});
}

/// Screen 09 — "three decisions, one confirm" before a room is created,
/// replacing what used to be an immediate startWatchTogether() call from
/// five different buttons. Rendered as its own full screen rather than a
/// literal dialog over the dimmed detail page (same disclosed
/// simplification as PlaybackFailed). [server] is whichever server the
/// content being shared actually lives on (a room is always hosted off one
/// concrete copy). [defaultRestart] preselects the choice based on which
/// existing entry point was pressed (the plain "Watch Together" button vs.
/// a restart-together affordance) — exact resume timestamps aren't
/// threaded through from every call site, so the dialog offers
/// "Resume"/"Start from the beginning" generically rather than the
/// mockup's specific "Start from 46:12".
class WatchTogetherStart extends AppState {
  final LibraryContext ctx;
  final PlexServer server;
  final AppState returnState;
  final String roomTitle;
  final String? thumb;
  final String targetRatingKey;
  final bool defaultRestart;

  const WatchTogetherStart({
    required this.ctx,
    required this.server,
    required this.returnState,
    required this.roomTitle,
    this.thumb,
    required this.targetRatingKey,
    this.defaultRestart = false,
  });
}

class Lobby extends AppState {
  final PlexServer server;
  final PlexMovieDetail detail;
  final AppState returnState;
  final RelayClient relay;
  final String hostName;
  final String relayNickname;
  final String? thumb;
  final bool isHost;

  const Lobby({
    required this.server,
    required this.detail,
    required this.returnState,
    required this.relay,
    required this.hostName,
    required this.relayNickname,
    this.thumb,
    this.isHost = false,
  });
}

class Player extends AppState {
  final PlexServer server;
  final PlexMovieDetail detail;
  final AppState returnState;
  final RelayClient? relay;
  // Null when playing a movie. Set when playing an episode — the only
  // piece of show/season context that reaches the player at all today
  // (PlexMovieDetail itself carries no parent/grandparent linkage), just
  // enough for screen 16's real fetchNextEpisodeForShow lookup.
  final String? showRatingKey;

  const Player({required this.server, required this.detail, required this.returnState, this.relay, this.showRatingKey});
}
