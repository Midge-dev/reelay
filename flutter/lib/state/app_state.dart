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

  const SectionGroup({
    required this.type,
    required this.title,
    required this.sectionsByServerId,
  });

  String get key => '$type::${title.toLowerCase()}';

  PlexSection? sectionOn(String machineIdentifier) =>
      sectionsByServerId[machineIdentifier];
}

/// Unions same-(type,title) [PlexSection]s across every connected server
/// into rail-level [SectionGroup]s — see its own doc comment for why
/// (type, title), not type alone. [sectionsByServerId] is keyed by
/// [PlexServer.machineIdentifier]; a server with no sections fetched yet
/// (or none at all) is simply absent from every group.
List<SectionGroup> groupSections(
  Map<String, List<PlexSection>> sectionsByServerId,
) {
  final groups = <String, SectionGroup>{};
  final order = <String>[];
  for (final entry in sectionsByServerId.entries) {
    for (final section in entry.value) {
      final title = normalizeLibraryTitle(section.title);
      final key = '${section.type}::${title.toLowerCase()}';
      final existing = groups[key];
      if (existing == null) {
        groups[key] = SectionGroup(
          type: section.type,
          title: title,
          sectionsByServerId: {entry.key: section},
        );
        order.add(key);
      } else {
        groups[key] = SectionGroup(
          type: existing.type,
          title: existing.title,
          sectionsByServerId: {
            ...existing.sectionsByServerId,
            entry.key: section,
          },
        );
      }
    }
  }
  return [for (final k in order) groups[k]!];
}

final _tvPrefix = RegExp(r'^tv\s+(shows|series)$', caseSensitive: false);

/// The rail label for a server library: its own name, trimmed and with
/// runs of whitespace collapsed, minus Plex's default "TV " prefix — "TV
/// Shows" is Plex's stock name for a show library and reads as "Shows"
/// beside the other one-word destinations (the design's own rail labels are
/// all a single word). Anything else the owner named is left as they wrote
/// it.
String normalizeLibraryTitle(String raw) {
  final title = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final tv = _tvPrefix.firstMatch(title);
  if (tv != null) {
    final rest = tv.group(1)!;
    return rest[0].toUpperCase() + rest.substring(1).toLowerCase();
  }
  return title;
}

/// The servers/sections/selected-section/items bundle threaded through every
/// library-adjacent AppState. Widened for the multi-server hub: [servers]
/// is every connected server (not one), [sectionGroups]/[selectedSectionGroup]
/// union same-named libraries across them (see [SectionGroup]), and [items]
/// is folded by guid ([FoldedWork]) — a title on two servers is one entry
/// here with two copies, not two entries.
class LibraryContext {
  final List<ReachableServer> servers;
  final List<SectionGroup> sectionGroups;
  final SectionGroup selectedSectionGroup;
  final List<FoldedWork<PlexLibraryItem>> items;

  const LibraryContext({
    required this.servers,
    required this.sectionGroups,
    required this.selectedSectionGroup,
    required this.items,
  });

  LibraryContext copyWith({
    SectionGroup? selectedSectionGroup,
    List<FoldedWork<PlexLibraryItem>>? items,
  }) => LibraryContext(
    servers: servers,
    sectionGroups: sectionGroups,
    selectedSectionGroup: selectedSectionGroup ?? this.selectedSectionGroup,
    items: items ?? this.items,
  );
}

/// Every screen the app can be on. There is no Navigator or router — one
/// sealed state drives a single switch in AppRoot. `returnState` is the
/// back stack: Back restores the captured state (and re-fetches fresh data
/// for it); ScreenMemory restores how it was left.
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

  /// Part of first-run setup — rendered as screen O5 ("Ready — the work,
  /// itemised") rather than the plain loading screen.
  final bool firstRun;

  /// What has finished so far, in order, and what is under way — O5's
  /// checklist. Headline once the shape of the hub is known ("Two
  /// servers, five libraries").
  final List<String> done;
  final String? current;
  final String? headline;

  const ConnectingToServer({
    this.username,
    this.firstRun = false,
    this.done = const [],
    this.current,
    this.headline,
  });
}

/// An error screen with a way back: [retryState] is where Back (or retry)
/// goes, since every other screen supports Back and a dead end would be
/// jarring.
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

  /// Where you were on the title, so the offered copy carries on there.
  final int? resumeAtMs;

  const PlaybackFailed({
    required this.ctx,
    required this.server,
    required this.targetRatingKey,
    required this.fromStart,
    required this.reason,
    required this.returnState,
    this.resumeAtMs,
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
  final List<FoldedWork<PlexOnDeckItem>> onDeck;
  final List<FoldedWork<PlexLibraryItem>> recentlyAdded;
  final List<FoldedWork<PlexOnDeckItem>> recentActivity;
  final List<FoldedWork<PlexOnDeckItem>> suggestions;
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

  Home copyWith({List<FoldedWork<PlexOnDeckItem>>? onDeck}) => Home(
    servers: servers,
    sectionGroups: sectionGroups,
    onDeck: onDeck ?? this.onDeck,
    recentlyAdded: recentlyAdded,
    recentActivity: recentActivity,
    suggestions: suggestions,
    unreachableResources: unreachableResources,
  );
}

/// [returnState] is wherever the section was opened from — Back goes there
/// (it used to fall through to Android and leave the app).
class Library extends AppState {
  final LibraryContext ctx;
  final AppState returnState;

  const Library({required this.ctx, required this.returnState});
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

  const Settings({
    required this.ctx,
    required this.returnState,
    this.relayHint,
  });
}

/// Rail-level and reachable from anywhere — DESIGN.md screen 05.
class Search extends AppState {
  final LibraryContext ctx;
  final AppState returnState;

  const Search({required this.ctx, required this.returnState});
}

/// Screen 20 — a rail-level peer destination like Library; Back returns to
/// wherever it was opened from, same as Library. It "belongs to
/// the Plex account rather than to a server, so it spans every library at
/// once" (screen 20's own note) — [ctx] is only used for its
/// servers/sections, to resolve a tapped item the same way Home's existing
/// `selectWatchlistItem` already did; selectedSectionGroup/items are
/// irrelevant here.
class Watchlist extends AppState {
  final LibraryContext ctx;
  final AppState returnState;

  const Watchlist({required this.ctx, required this.returnState});
}

/// [work] is every known copy of this title across connected servers;
/// [activeCopy] is which one detail is actually loaded from (fold's
/// reachability-priority pick by default — see duplicate_fold.dart).
/// Screen 03d's source picker (when built) lets the user override
/// [activeCopy] to another of [work]'s copies without losing [work] itself.
///
/// [resumeAtMs] is how far in you are on the *title* when that came from
/// another copy (a source switch, screen 25's offer) — progress belongs to
/// the title, not the file, so the page resumes from the furthest of it
/// and this copy's own. [showSources] opens 03d over the page on arrival.
class MovieDetail extends AppState {
  final LibraryContext ctx;
  final FoldedWork<PlexLibraryItem> work;
  final Sourced<PlexLibraryItem> activeCopy;
  final AppState returnState;
  final int? resumeAtMs;
  final bool showSources;

  const MovieDetail({
    required this.ctx,
    required this.work,
    required this.activeCopy,
    required this.returnState,
    this.resumeAtMs,
    this.showSources = false,
  });
}

/// Screen 03c. [server] is the server [person] was picked on — their tag
/// id there is where the search across every connected server starts
/// (PersonCredits); the page gathers its own titles.
class PersonFilmography extends AppState {
  final LibraryContext ctx;
  final PlexServer server;
  final PlexPerson person;
  final AppState returnState;

  const PersonFilmography({
    required this.ctx,
    required this.server,
    required this.person,
    required this.returnState,
  });
}

class CollectionDetail extends AppState {
  final LibraryContext ctx;
  final Sourced<PlexCollection> collection;
  final List<PlexLibraryItem> items;
  final AppState returnState;

  const CollectionDetail({
    required this.ctx,
    required this.collection,
    required this.items,
    required this.returnState,
  });
}

/// [episode] is fetched from [activeCopy]'s server — same single-server
/// simplification as [PersonFilmography] (see its doc comment). [work] is
/// every known copy of the show, same shape as [MovieDetail.work].
class EpisodeDetail extends AppState {
  final LibraryContext ctx;
  final FoldedWork<PlexLibraryItem> work;
  final Sourced<PlexLibraryItem> activeCopy;
  final PlexEpisode episode;
  final AppState returnState;

  const EpisodeDetail({
    required this.ctx,
    required this.work,
    required this.activeCopy,
    required this.episode,
    required this.returnState,
  });
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

  const Player({
    required this.server,
    required this.detail,
    required this.returnState,
    this.relay,
    this.showRatingKey,
  });
}
