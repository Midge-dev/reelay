import '../data/plex/plex_models.dart';
import '../sync/relay_client.dart';

/// Ports MainActivity.kt's private `LibraryContext` data class — the
/// server/sections/selected-section/items bundle threaded through every
/// library-adjacent AppState.
class LibraryContext {
  final PlexServer server;
  final List<PlexSection> sections;
  final PlexSection selectedSection;
  final List<PlexLibraryItem> items;

  const LibraryContext({required this.server, required this.sections, required this.selectedSection, required this.items});

  LibraryContext copyWith({PlexSection? selectedSection, List<PlexLibraryItem>? items}) => LibraryContext(
        server: server,
        sections: sections,
        selectedSection: selectedSection ?? this.selectedSection,
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

class RelaySetup extends AppState {
  final LibraryContext ctx;

  const RelaySetup({required this.ctx});
}

class Home extends AppState {
  final PlexServer server;
  final List<PlexSection> sections;
  final List<PlexOnDeckItem> onDeck;
  final List<PlexLibraryItem> recentlyAdded;
  final List<PlexOnDeckItem> recentActivity;
  final List<PlexOnDeckItem> suggestions;

  const Home({
    required this.server,
    required this.sections,
    required this.onDeck,
    required this.recentlyAdded,
    required this.recentActivity,
    required this.suggestions,
  });

  Home copyWith({List<PlexOnDeckItem>? onDeck}) => Home(
        server: server,
        sections: sections,
        onDeck: onDeck ?? this.onDeck,
        recentlyAdded: recentlyAdded,
        recentActivity: recentActivity,
        suggestions: suggestions,
      );
}

class Library extends AppState {
  final LibraryContext ctx;

  const Library({required this.ctx});
}

class LoadingSection extends AppState {
  final PlexServer server;
  final List<PlexSection> sections;
  final String? selectedSectionKey;
  final AppState returnState;

  const LoadingSection({required this.server, required this.sections, this.selectedSectionKey, required this.returnState});
}

/// Shown while `goHome`'s fetches are in flight — mirrors [LoadingSection],
/// which Home previously had no equivalent of: `goHome` used to hold on a
/// single `_setState` until every fetch resolved, so re-selecting Home from
/// the nav drawer showed nothing changing (and kept the drawer visually
/// expanded, since nothing became focusable to pull focus off the rail).
class LoadingHome extends AppState {
  final PlexServer server;
  final List<PlexSection> sections;

  const LoadingHome({required this.server, required this.sections});
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

class MovieDetail extends AppState {
  final LibraryContext ctx;
  final PlexLibraryItem movie;
  final AppState returnState;

  const MovieDetail({required this.ctx, required this.movie, required this.returnState});
}

class PersonFilmography extends AppState {
  final LibraryContext ctx;
  final PlexPerson person;
  final List<PlexLibraryItem> items;
  final AppState returnState;

  const PersonFilmography({required this.ctx, required this.person, required this.items, required this.returnState});
}

class CollectionDetail extends AppState {
  final LibraryContext ctx;
  final PlexCollection collection;
  final List<PlexLibraryItem> items;
  final AppState returnState;

  const CollectionDetail({required this.ctx, required this.collection, required this.items, required this.returnState});
}

class EpisodeDetail extends AppState {
  final LibraryContext ctx;
  final PlexLibraryItem show;
  final PlexEpisode episode;
  final AppState returnState;

  const EpisodeDetail({required this.ctx, required this.show, required this.episode, required this.returnState});
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

  const Player({required this.server, required this.detail, required this.returnState, this.relay});
}
