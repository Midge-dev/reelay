# Reelay — Architecture & Design Notes

> **2026-09-20: superseded by the Flutter rewrite.** Everything below
> describes the original native Kotlin/Jetpack Compose implementation
> (`app/` + `shared/`), which has been retired — the app is now a single
> Flutter project at `flutter/`. This document is kept because most of the
> *reasoning* here (focus-navigation hazards, relay/sync protocol design,
> the watch-together timing model, hard-won platform gotchas) carried
> straight over into the port and is still the best record of *why* things
> work the way they do, even though the Kotlin-specific code paths it
> references no longer exist. See `flutter/` for current source, and the
> Flutter test suite for what's actually verified today. If a section here
> turns out to no longer apply even conceptually, prefer trusting the
> current code over this doc.

This document exists because the codebase's comments used to carry this
knowledge inline, one decision at a time, next to the code it explained. That
made sense while a decision was fresh, but it scattered the reasoning behind
this app's design across dozens of files with no way to see the whole picture
at once. This is that picture: why the app is built the way it is, not just
what the code does.

## 1. Project shape

The codebase is split across three parts:

- **`app/`** — the Android TV client: Jetpack Compose UI, platform glue
  (`MainActivity`, ExoPlayer wiring, secure token storage), and the custom
  design system (`ui/kit`).
- **`shared/`** — a Kotlin Multiplatform `commonMain` module: the Plex API
  client, the relay sync client and wire protocol, the host-authoritative
  playback sync engine, and settings persistence. Everything here is meant to
  be reusable by a future tvOS target, so it avoids JVM-only APIs
  (`java.net.URI`, `java.util.UUID`, JVM-only time APIs) even where an
  Android-only shortcut would have been shorter.
- **`relay/server.js`** — a small, self-hosted Node WebSocket server. One
  deployment serves one friend group, hosting many independent Watch Together
  rooms at once. It's explicitly *not* a hardened public multi-tenant
  service, but it is often reachable from the open internet (users configure
  arbitrary relay URLs, including cloud-hosted ones), so real security
  hygiene still matters — see §6.3.

## 2. App navigation & state machine

`MainActivity.kt`'s `AppState` is a sealed interface, and one `when` block in
`AppRoot` drives every screen transition off it. A few things about its shape
are load-bearing:

- **`LibraryContext`** bundles the four fields every library-browsing state
  needs (server, sections, selected section, items) so each `AppState`
  variant doesn't repeat them.
- **`Home`** is the landing screen after login and the only state not scoped
  to a `LibraryContext` — it carries its own row data (on-deck, recently
  added, suggestions) and is always refetched on entry, since watch progress
  and library contents change constantly.
- **`LoadingSection`** exists because fetching a section's items and
  preloading its posters can take a visible moment; without this state,
  nothing changed on screen until both finished, reading as an unresponsive
  pause. It carries which section is being loaded *into* so the nav drawer
  can highlight the right destination while it waits.
- **`returnState`** is threaded through `Settings`, `MovieDetail`,
  `PersonFilmography`, `Lobby`, and `Player` because each of those is
  reachable from more than one place (Home *and* Library, for instance), so
  Back has to resolve to wherever the screen was actually opened from, not a
  hardcoded parent. `ShowSeasons`/`ShowEpisodes` carry `returnState` through
  unchanged, since their own Back already steps back one level internally.
- **`EpisodeDetail`** exists because a room is a social act with a cost — the
  episode about to be started has to be legible (synopsis, runtime, resume
  point) before the press, not confirmed after it. Pressing an episode in
  `ShowEpisodesScreen` lands here instead of jumping straight to `Player`.
- **`Lobby.relay`** is non-null by construction (a Lobby only exists once a
  relay connection is real); **`Player.relay`** stays nullable because Player
  is also reachable directly, skipping Lobby, when no relay is configured —
  solo playback has never depended on one. The `RelayClient` itself is shared
  across the Lobby → Player transition (via `ensureRelayClient`) so the
  connection and any active chat don't reconnect on every screen change.

### Splash screen

`SPLASH_MIN_HOLD_MS` (1400ms, per the design spec) is a *floor*, not a
ceiling: the entrance animation always gets to finish before the cross-fade
to Home, but a slower Plex-token check just holds the splash at its settled
end frame for however much longer is needed. Two real problems showed up in
testing and got fixed together: the entrance felt "barely readable as
animation, and cut off" because the motion was too subtle (small scale
deltas, a 10dp rise) and every stage finished by ~1080ms, leaving the last
~300ms of the hold as a dead static frame — a glance from the couch could
land entirely inside "nothing moving." The fix was bigger deltas plus a
continuous breathing pulse (`BREATHE_PERIOD_MS`) that runs for as long as the
screen is up, independent of the one-shot entrance — because a real Plex
token check (DNS, TLS, a remote server) can genuinely take longer than
1.4s, and without a continuous pulse the screen would sit dead still for
however much longer that takes.

The wordmark renders from a raster PNG rather than live type, because the
design spec explicitly names it "the raster fallback for platforms without
the font" — nothing in this app bundles Space Grotesk, and adding a font
just for a 1.4s splash isn't worth it. The logo mark itself is sized by width
plus its real aspect ratio (1181×696, ~1.7:1) rather than forced into a
square box, which is what previously made it look squashed and cropped.

### Compose window setup

`WindowCompat.setDecorFitsSystemWindows(window, false)` (edge-to-edge) exists
so the player's video surface can claim the entire physical display —
otherwise space reserved for system bars shows up as extra black bars on top
of whatever letterboxing is already baked into the video. The root
`CompositionLocalProvider(LocalContentColor provides AppOnBackground)`
matters because a plain `Modifier.background()` doesn't establish content
color on its own; without it, every bare `Text()` outside a themed control
falls back to Compose's hardcoded default (black), unreadable on this dark
theme.

## 3. Custom design system (`ui/kit`) vs Material3

`ui/kit` replaces tv-material3 *and* base Material3 entirely with a
hand-owned component library. This wasn't a stylistic preference — several
concrete problems forced it:

- tv-material3's default dark color tokens are tuned for close-up phone
  viewing and read low-contrast from a couch on a real TV panel.
- The borrowed `FilterChip`'s shape defaulted to an 8dp-corner rect instead
  of the design's pill shape — a real bug found during a spec audit.
- tv-material3's `Card` exposes only a single `onClick`, no `onLongClick` —
  confirmed by decompiling the library artifact — which is why Continue
  Watching's long-press-to-remove and the nav rail's own sidebar are both
  hand-rolled with `combinedClickable` instead of `Card`.
- The base (non-TV) Material3 `ContainedLoadingIndicator` this app used to
  borrow reads as a visibly different, non-native component next to
  everything else.
- Neither tv-material3 nor base Material3 has a scrollbar widget at all,
  hence `NeonScrollbar`.

`Icon` and `Text` replace their tv-material3 equivalents with the same call
shape (imageVector/contentDescription, positional text plus the handful of
named params every call site actually uses) specifically so migrating a
screen was an import swap, not a rewrite. `LocalContentColor` replaces
Material's theme-based content-color propagation as a plain
`CompositionLocal`, since this app's palette is just the flat `AppColors.kt`
constants — there's no `ColorScheme`/`Typography` bundle to carry alongside
it. `ShumTypography` encodes the design spec's role hierarchy as normative
(headline/body roles) with per-platform absolute sizes; a future tvOS/Roku
port would map the same six roles to its own platform sizes rather than
reusing these numbers directly. No custom font is used — the spec's own
mockup calls for "the platform default sans," which on Android is Roboto.

### `FocusableSurface` — the shared focus/color/border/glow contract

Every kit component that can take D-pad focus (`Button`, `Card`,
`ListItem`, `FilterChip`) is built on `FocusableSurface`, which owns
interaction-source-driven focused/pressed/selected/disabled state and turns
it into a container color, content color, border, and glow. D-pad
center/enter → click needs nothing special here — plain
`Modifier.clickable`/`combinedClickable` already works for TV, which
`HomeScreen`'s `ContinueWatchingPoster` proved out before this file even
existed. `ShumColors` deliberately mirrors tv-material3's
`ButtonColors`/`ListItemColors` shape, so it's a familiar mental model for
anyone who's worked with those, just owned by the app now instead of
borrowed.

The glow (`ShumGlow`) is hand-drawn, not Android's native elevation shadow —
`Modifier.shadow`'s ambient/spot tint is a platform compositor effect that
isn't fully controllable, and changing its elevation produced no visible
difference on real hardware. The radius/alpha defaults match the design
spec's focused box-shadow almost exactly and reliably reproduce on every
device; one default cascades to every `ShumGlow()` call site, so there's one
place to retune it later.

### The `drawGlow` technique

Compose's real blur (`Modifier.blur`, RenderEffect-based) needs API 31+, and
this app's `minSdk` is 26, so `drawGlow` fakes a soft blur by layering the
surface's own shape outward at shrinking size and growing alpha. It's not
private, because `HomeScreen`'s `RoomCard` hand-rolls its own card-level
focus tracking (a `focusGroup()` of several independent buttons, not one
`FocusableSurface`) but still needs the identical glow, not an
approximation.

The technique itself: each shell is a flat-alpha fill, largest first, so a
point at distance *d* from the surface's edge ends up covered by every shell
whose expansion is ≥ *d* — the visible falloff comes from composited "over"
blending across that many stacked shells, not any single shell's own alpha.
Using 14 thin shells (not 3) turns that into a smooth gradient instead of 1–2
visible concentric rings. A squared falloff front-loads the fade near the
edge, matching how a real glow reads brightest close-in rather than evenly
ramped across the full radius; a fitted peak constant keeps the *composited*
brightness at the surface's edge matching the requested alpha, not just each
shell's own small contribution. A rounded shape's corner radius has to grow
by the same `expand` value as the shell itself — otherwise a small corner
radius on an increasingly bigger rectangle reads as progressively squarer at
each shell, making the outer (most visible) part of the glow look
corner-cut instead of round. `CircleShape` and other shapes don't have this
problem (a circle offset outward is still a circle), so only
`RoundedCornerShape` is special-cased.

### Individual components (brief)

- **Button** — pill shape, white label in every state, 2dp focus stroke.
  Filled buttons never expose colors/border/glow params (the whole point is
  one theme, not a per-call-site configuration surface). `compact` is an
  opt-in smaller footprint for tight multi-action contexts (e.g. RoomCard's
  Join/End-session pair), not the default, since most buttons have room to
  breathe at standard size.
- **Card** — posters never change container fill on focus, only the
  gradient border + glow (unlike buttons, which solid-fill). Focus
  magnification is scale-only, animated with a spring (not a fixed tween) so
  the settle feels like a physical nudge, slight overshoot intentional. Never
  dips below 1f on press — a press is a colour change only, so nothing ever
  looks like it retreats from the viewer.
- **FilterChip** — idle muted, selected keeps the fill and adds a leading
  checkmark, focused takes the standard solid-fill + gradient border/glow
  pair. Its compact padding exists because it has exactly one caller
  (Settings' bitrate row) that needs all four presets to fit on screen at
  once without a horizontal scroll.
- **IconButton** — player transport controls only: transparent at rest so
  icons float over video with no visible container until focused.
- **ListItem** — the nav rail's own row language, reused anywhere a
  selectable row appears (Settings' server list, the player's subtitle/
  quality pickers).
- **Switch** — track color is already spoken for by on/off state, so a press
  shrinks the thumb instead, since that's the only tone left to carry "a
  press just landed."

### `AppColors`

Every color literal in the app routes through this one file. `AppWhite`/
`AppScrim` are plain white/black, deliberately separate from the near-white/
near-black `AppOnBackground`/`AppBackground` tokens — content sitting
directly on photos, video, or a QR code (overlay text, scrims, QR
backgrounds) wants literal contrast, not the app-chrome-tuned off-white used
for body text. `NeonPurpleGradient` (radial, focus borders/glow) and
`NeonPurpleProgressGradient` (linear, Continue Watching's resume fill) are
both built from the same two base tones so a single place controls the
whole app's two-tone treatment.

## 4. Focus management on Android TV

This is the single most recurring category of bug and fix in this codebase,
so it gets its own section rather than being scattered per-screen. See
`docs/focus-navigation-qa-checklist.md` for these same bug classes written
up as a framework-agnostic QA checklist, for testing any future UI rewrite
(e.g. a Flutter port) against the same failure modes.

### The hazard

`AppNavigationDrawer`'s sidebar is a persistent, always-focusable element
wrapping every browsing screen. Whenever a composable that currently owns
D-pad focus gets destroyed or swapped out mid-composition — a confirm
overlay closing, a dropdown closing, a whole pane swapping to another — and
nothing explicitly claims the next focus target, Compose's focus-loss
fallback can search all the way out to the nav rail and land there. Landing
there and immediately bouncing back reads to the user as the drawer
flickering open, or a remote press "randomly opening the nav drawer." This
exact bug class was found and fixed in most of the app's transient-UI spots
this session:

- `HomeScreen`'s `RoomCard` action row (`up = FocusRequester.Cancel`, since
  there's nothing focusable above it to search into).
- `ContinueWatchingPoster`'s and `WatchlistPoster`'s `RemoveConfirmOverlay`
  (`focusProperties { onExit = { cancelFocusChange() } }`, trapping any
  outgoing focus search while the overlay is up) — but that trap alone
  wasn't sufficient (see below).
- Settings' Maximum-seats menu (`LaunchedEffect(maxSeatsMenuExpanded)`
  explicitly restores focus to the row that opened it, on close).
- The phone-pairing QR flow's Cancel button, in **both** `SettingsScreen`
  and `RelaySetupScreen` — closing the panel (via a successful phone submit
  *or* the Cancel button) removes it, and whichever button had focus, from
  composition. Both call sites now explicitly `requestFocus()` onto a stable
  target afterward.
- `PlayerScreen`'s `SubtitleMenu`/`BitrateMenu` — these used
  `FocusRequester.Default` at list boundaries and never set left/right at
  all, so Up/Down at the ends or any Left/Right while a menu was open could
  escape past it. Fixed to `FocusRequester.Cancel` on every boundary,
  matching the correct pattern already used in `LibraryScreen`'s Sort/Filter
  menus.
- `RelayStatus`'s Failed branch (Retry / Host-on-another-relay) — trapped
  with `onExit = { cancelFocusChange() }` rather than a specific redirect
  target, since this component is shared between Lobby and Settings and
  doesn't know a sibling to point to.

The vocabulary that resulted: an explicit `up`/`down`/`left`/`right` =
`FocusRequester.Cancel` at a list or menu's edges consumes a key press
instead of letting the search continue outward; `focusProperties { onExit =
{ cancelFocusChange() } }` traps an outgoing search from inside a transient
overlay while it's still composed; and an explicit
`LaunchedEffect` + `requestFocus()` restores focus to a named target the
instant a whole pane or overlay closes. Which one applies depends on whether
there's a specific place to send focus back to (use the explicit restore) or
not (use the trap).

### The retry-across-frames pattern

A focus grab that targets a *different* composable than the one requesting
it — reopening a sub-screen, jumping from a settings row into a freshly
opened pane — often runs before that target is actually composed yet on the
very first frame. A single un-retried `requestFocus()` in that situation
silently fails, leaving focus stuck wherever it was (often the nav rail).
The fix used everywhere this comes up is the same small loop:
`repeat(5) { if (runCatching { it.requestFocus() }.isSuccess) return@repeat;
withFrameNanos {} }`.

### Every browsing screen claims initial focus explicitly

Because the nav rail is the first focusable element in composition order,
every screen it wraps (`LibraryScreen`, `MovieDetailScreen`,
`PersonFilmographyScreen`, `ShowEpisodesScreen`, `ShowSeasonsScreen`,
`EpisodeDetailScreen`, `SettingsScreen`) has its own `LaunchedEffect` that
explicitly requests focus onto its own content on entry, keyed on whatever
identifies "a new instance of this screen" so re-entering with different
content re-focuses too. `HomeScreen` picks its initial target dynamically —
whichever row is first non-empty in display order (Watch Together →
Continue Watching → Recently Added → Suggestions) — so focus always lands on
a real card.

### Bringing the *whole* focused thing into view

A `LazyColumn`'s default "bring the focused child into view" behavior only
guarantees the specific focused element's own small rect is visible, not
necessarily the visual unit it belongs to. Two examples: `RoomCard`'s Join
button sits well below the card's own top edge (poster, host row, relay line
all come first), so it uses an explicit `BringIntoViewRequester` on focus to
scroll the whole card into view, not just the button. `MovieDetailScreen`'s
hero-focus-scroll-to-top does the analogous thing with `scrollToItem(0)`,
using a token counter rather than a boolean — a boolean flipping false→true
only fires once per visit, so moving focus between two buttons that are
both already "true" (e.g. Play → Watch Together) never re-triggered the
correction, and the lazy list's own built-in adjustment won that case
uncontested instead.

## 5. Screens

### Home

Six stacked rows inside one `LazyColumn`, in priority order: Watch Together,
Watchlist, Continue Watching, Recently Finished Watching, Recently Added,
Suggestions — a plain `Column` was tried first and felt "static," since
nothing scrolled and no off-screen focus target could be brought into view
once a row scrolled past the bottom edge. Watch Together and Watchlist
self-hide entirely (render nothing) when empty, same as `HomeRow`'s generic
empty-list guard used by the other four. Room polling (§6.2) refreshes every
5 seconds independent of scroll position, so a room can appear while the
user is scrolled down elsewhere; a dedicated `LaunchedEffect` keyed on a
derived `watchTogetherGetsFocus` boolean (not the raw `liveRooms` list,
which gets a new instance on every poll tick even when nothing changed)
waits for a short quiet-input window (1.2s — tuned up twice from an initial
800ms after it still felt like it fired mid-navigation) so it never yanks
focus out from under active D-pad navigation, then scrolls to the top and
steals focus onto the first room card. That scroll uses a small
`LazyListState.scrollToTopSlowly()` helper instead of a bare
`animateScrollToItem(0)`, which has no public duration/easing knob — the
helper reads `layoutInfo.visibleItemsInfo` for item 0's current `offset`
(only present when item 0 is still partially laid out, i.e. the user hasn't
scrolled more than roughly a screen's worth of rows past it) and drives that
exact distance through `animateScrollBy(offset, tween(1.1s,
FastOutSlowInEasing))` for a deliberately slow, purposeful-looking scroll.
Overshooting this distance (e.g. always requesting a huge negative value and
relying on `animateScrollBy` clamping at the top) was tried and rejected: the
clamp happens as soon as the *cumulative* animated value exceeds the real
distance, and with a huge requested value an easing curve's early frames
already blow past a small real distance, so the scroll looks instantaneous
instead of taking the full duration. When item 0 isn't laid out at all (user
scrolled further away), it falls back to the plain unthrottled
`animateScrollToItem(0)` — correctness (always landing exactly at the top)
wins over a calibrated duration in that rarer case, since there's no cheap
way to know the real distance without it being currently measured. Every
other row-content list
change (watchlist mutated, `onDeck` mutated, a room removed) is deliberately
kept out of that same effect's key list — an earlier version folded them all
into one `LaunchedEffect`, so any Watchlist removal while a room was live
re-ran the *whole* effect, including the quiet-wait-then-scroll-to-Watch-Together
dance, even though nothing about Watch Together had changed.

Continue Watching's, Watchlist's, and `RoomCard`'s long-press/click-triggered
remove flows needed several small fixes to feel reliable on a real remote.
The physical button that triggers a long press is usually still held down
right when the confirm overlay appears — its eventual release lands on
whichever button the overlay just focused, and without a guard that stray
release reads as a real click before the user ever chose anything.
`confirmArmed` solves this by swallowing the *exact* trailing release tied
to the gesture that opened the overlay (a time-based debounce doesn't work,
since hold duration varies), caught via `onPreviewKeyEvent` so it's seen
before Remove/Cancel's own clickable can treat it as a click.

A second, larger issue turned out to share one root cause across all three
cards: `AppNavigationDrawer`'s rail width is driven by a bare
`onFocusChanged { expanded = it.hasFocus }` on its own Column — it reacts to
*any* focus landing anywhere in that subtree, even for a single frame.
`RoomCard` is similarly hair-triggered (it calls
`bringIntoViewRequester.bringIntoView()` on its own `onFocusChanged`). The
original `WatchlistPoster`/`ContinueWatchingPoster` swapped `if
(confirmingRemove) RemoveConfirmOverlay(...) else { artwork + clickable Box
}` — but the clickable Box, not the outer wrapping Box, was the actual focus
target, so flipping `confirmingRemove` disposed the currently-focused node
for one frame on *both* open and close. Compose's default focus search fills
that gap with whatever's nearest before any of the app's own reactive
refocus code gets a chance to run — landing on the nav rail (which then
flickers open) or, if a Watch Together room happened to be live, on its
`RoomCard` (which then auto-scrolls into view). `hasBeenFocusedSinceConfirm`
predates this fix and guards a related but narrower case (a transient
no-focus frame being misread as "the user backed out"); it did not prevent
the rail/RoomCard flicker on its own. The fix: never let an `if`/`else`
content swap remove the currently-focused interactive element. The
clickable artwork surface (and, for `RoomCard`, its action row) now stays
mounted continuously; `RemoveConfirmOverlay` layers on top of it instead of
replacing it, and every `FocusRequester` — both the externally-supplied
"give this initial focus" one and each card's own internal
"restore-focus-here-on-cancel" one — is attached to that same
always-present focusable leaf, never to the outer `.focusGroup()`-only
wrapper (which isn't itself a valid `requestFocus()` target).

Actually *removing* a row item (Remove, or `RoomCard`'s End session) is a
real data change, not just a same-item state toggle, so the "keep it
mounted" trick doesn't apply — the item's composable legitimately goes away.
Each removable row instead keeps its own always-attached index-0
`FocusRequester`, independent of which row the home screen's overall
initial-focus priority chain currently favors, and a small
`LaunchedEffect` per row watches that row's item *count* (not the list
reference, which can change on unrelated refreshes/polls) and re-requests
that anchor focus only when the count just decreased and the row is still
non-empty — landing focus back inside the row instead of wherever Compose's
disposal search would otherwise send it. When a row empties out completely
instead (e.g. the last Watch Together room ends), the home-level priority
booleans recompute reactively and the top-level `firstItemFocus` effect
picks up the newly-promoted row on its own.

`RoomCard` (design spec §11) is one unified 300dp card for every room,
hosted or not — an earlier draft put hosted rooms in their own strip with
different components, which was scrapped in favor of one card shape with one
extra button. A room you host reads as yours from three things: a "You're
hosting" badge, "You hosting" replacing the host line, and a second action
(End session) — Join always keeps its place, weight, and label, so the first
thing under focus is always the way in, never the way to end it. End session
has no confirmation step: it ends the room immediately regardless of who's
seated, and failure is quiet (the card stays, its dot greys, the button
reads "Can't reach relay" for four seconds, then reverts) rather than
blocking on a retry queue.

`RoomCard`'s outer container is a `Box`, not a `Column`, and its artwork
region is drawn 2dp taller than its nominal 104dp. This is a fix for a
GPU-scaling seam: the card's whole subtree sits under one `graphicsLayer`
scale (the focus-magnify animation), and at a non-1.0 scale factor the
boundary between the artwork and the info panel below it landed on a
fractional pixel row, producing a faint but real horizontal band a few
pixels tall and visibly brighter than either neighboring region (confirmed
via pixel sampling on-device, not just eyeballing). Matching the scrim's end
color to the panel's background did not fix it — the seam persisted
regardless of color, confirming it's a rendering-boundary artifact, not a
color mismatch. The fix instead relies on deliberate overlap: the info
panel's `Column` is positioned with `padding(top = 104.dp)` and paints its
own opaque `AppSurface` background starting at that line, so it draws over
(in z-order, since it's the second `Box` child) whatever the artwork's
extra 2dp rendered at the boundary, regardless of the exact GPU mechanism
causing the bleed.

### Library

Sort and Filter are independent `BackHandler`-gated menus (only one open at
a time), each reopening with focus already on whatever's currently applied
rather than the first row. Their D-pad contract is deliberately closed: Up/
Down move within the menu without wrapping, Left/Right do nothing, so a
stray press can't jump to the grid behind it — implemented via
`FocusRequester.Cancel` on every boundary. Filter stays open on select
(unlike Sort) so several groups can be set in one visit. The overlay dims
rather than hides the grid behind it, and the grid stays mounted (empty)
behind a "Nothing matches" message rather than swapping to an illustration.

### Movie Detail

Play and Watch Together are peers, not a mode toggle: Play always goes
straight to solo playback with the relay untouched (it must never require
one configured), while Watch Together is the only path into the Lobby and
stays focusable — never disabled — even with no relay configured, routing to
Settings instead, since a disabled control gives a couch user nothing to act
on. Every section below the hero (Cast & Crew, Ratings & Reviews, Related,
More-with-actor rows) self-hides when its data is empty or hasn't arrived
yet; personal-media libraries routinely have none of this data, and that's
the normal case, not a broken one.

The co-star row dedup logic exists because Plex auto-generates a same-actor
hub for whichever cast member it internally picks — confirmed against a real
server to *not* reliably be the top-billed (index 0) entry. Assuming index 0
caused the same actor to get both the auto hub and a manually-built one,
showing as back-to-back duplicate "More with `<name>`" rows; the fix reads
the hub titles Plex actually returned and skips whoever's already covered
there.

### Person Filmography, Show Seasons/Episodes, Episode Detail

Person Filmography is a plain grid rather than reusing `LibraryScreen`'s
sort/filter UI, since a person-filtered view isn't "browsing a section" and
has no natural nav-drawer highlight. `EpisodeDetailScreen` exists because a
show's "Watch Together" used to start a room on whatever episode happened to
be on deck — the wrong grain, since rooms are about a specific episode.
It reuses the same hero shape as Movie Detail's, plus one kicker line naming
the show/season/episode, and a Resume/Play-from-start choice driven by the
episode's own `viewOffset`. Episode rows show a 4dp resume progress bar
identical to Continue Watching's, rendered only when there's an actual
resume point.

### Lobby

A skippable waiting room that never blocks solo viewing — Start Movie is
always enabled. The relay connection is owned above this screen (in
`MainActivity`'s `AppRoot`) so it survives the transition into `PlayerScreen`
instead of reconnecting. Room-closed handling distinguishes an explicit host
close (`ROOM_CLOSED`) from the room simply being gone by the time a reconnect
lands (`ROOM_NOT_FOUND`) — without this, whoever's waiting would see a
generic "Can't reach relay" failure that reads as a connectivity problem
rather than the deliberate end it actually was. The background art is the
title's own backdrop (or a blurred/cropped poster as fallback) under a
vertical scrim, replacing what used to be a bundled generic drawable. The
phone-facing chat QR is a dedicated full-screen modal rather than an inline
panel, because the lobby's vertically-centered, roster-sized content column
could otherwise push an inline QR row outside the screen's safe area on real
TV overscan — confirmed on-device, both the QR and its URL got cut off.

### Player

The entire on-screen chrome is hand-rolled Compose, not Media3's
`PlayerControlView` (used only as `useController=false`) — the built-in
controller fought this screen's own state at every turn: a D-pad press while
it wasn't yet "fully visible" got silently eaten, and its subtitle button
re-grayed itself any time ExoPlayer reported zero *native* text tracks,
exactly the burn-required/transcoded cases this app's own subtitle picker
exists to handle. Owning the whole surface means there's exactly one system
deciding what a keypress does.

A single D-pad tap on rewind/forward moves 10 seconds; holding the key grows
the step over time (10s → 20s at repeats 1–7 → 45s at 8–19 → 90s beyond),
driven by `KeyEvent.repeatCount`, matching the "hold to fast-seek" feel of
major streaming apps rather than crawling through a movie 10 seconds at a
time. While controls are hidden, Left/Right seek immediately without
requiring the chrome to be revealed first (a navigation aid, not a gate);
Select/Enter is a deliberate "reveal and act" gesture that toggles playback
in the same press that reveals the chrome.

Selected subtitle stream is stored per-device, never written back to Plex's
shared account state — this is what lets each viewer in a watch-together
room pick their own subtitle language independently while watching the same
item. Only a genuine mode change (direct-play ↔ transcode, switching burn
streams, or changing bitrate mid-transcode) rebuilds the whole ExoPlayer
session; switching between two directly-played text tracks patches into the
running player in place instead, since there's no live "reopen the HLS
session at a new bitrate" API to lean on.

The final "stopped" playback report on Back had a real bug, now fixed: it
was launched on `rememberCoroutineScope()`, which gets cancelled the instant
`onExit()` disposes the whole `PlayerSession` on the next recomposition — a
real network round-trip almost never completed before that cancellation
landed, so the one report meant to be authoritative silently never sent,
leaving Plex's resume point up to `REPORT_INTERVAL_MS` (5s) stale. The fix
wraps that specific call in `withContext(NonCancellable)`.

### Settings

Groups are ordered by how often each is touched (libraries/relays change;
playback/chat are set once), with deliberate spacing so the space *above* a
group is always larger than the space *inside* it — that asymmetry is what
actually creates visual grouping. Relay settings live in their own
sub-screen with a back breadcrumb (design spec §09d) so the relay list never
lengthens the top-level Settings column as relays are added; none of the
actual relay behavior changed when this became a sub-screen, only where it
renders.

Per-relay `FocusRequester`s are keyed by the relay's stable `id`, not by the
relay list itself — keying on the list would rebuild every `FocusRequester`
whenever *any* entry's fields changed (`RelayEntry` is a data class, so
flipping `isDefault` changes list equality), orphaning whichever row
currently held focus. Relay list changes (make-default, remove, edit) write
through to persistence immediately rather than waiting on the screen's Save
button, so Home's room-polling loop never disagrees with what Settings
displays; the Maximum-seats menu, by contrast, stages its change into the
in-progress `settings` var and only persists on Save, since it's a plain
setting like bitrate with no live-sync requirement.

### Navigation rail

Replaces an older top-of-screen tabs row, matching the collapsed-rail-that-
expands-on-focus pattern used by the major streaming apps instead of top
navigation. A previous hand-rolled version had a "stretch flash" bug on
entry, traced to two independently-timed animations (a width tween, a label
fade) racing each other off separate focus signals; the fix drives both from
the exact same `expanded` boolean read at the rail's root, so there's
structurally nothing left to race. Rail item color alone carries focused/
selected/idle state — text and icon stay plain white in every state, after
an earlier two-tone text treatment turned out low-contrast and hard to read
on real hardware (confirmed via photos, not just a screenshot glance) and
was flagged as an accessibility issue.

### Auth / first-run relay setup

Watch-together relay setup is shown once, immediately after Plex login, when
no relay is saved yet — making it part of first launch instead of something
only discovered later in Settings. "Skip for now" stays available
deliberately: sync has always been a bonus on top of local playback, never a
requirement.

## 6. Watch Together / relay sync system

### 6.1 Protocol & room intent model

Every device connection states its room intent up front
(`RoomIntent.Create`/`RoomIntent.Join`) rather than a single-tenant "hello"
envelope — one relay deployment hosts many independent rooms at once, each
identified by a `roomId` learned from Home's `/rooms` directory. `RelayEvent`
is one flat data class carrying every event kind (playback state, control
requests, peer status, clock ping/pong, chat) rather than a sealed
hierarchy — every field is optional anyway, and the relay itself never
inspects payload contents, just rebroadcasts them verbatim to every other
peer; whoever receives an event kind irrelevant to their role simply ignores
it. `ConnectionState.ROOM_CLOSED` is kept distinct from `ROOM_NOT_FOUND`:
both mean "this room is gone," but `ROOM_CLOSED` comes from an explicit
`"closed"` frame the relay sends the instant a host deliberately ends a
session, a clean signal rather than the transient-looking dropped-socket
path `ROOM_NOT_FOUND` covers.

### 6.2 Room/seat lifecycle (relay server)

A room lives as long as *anyone at all* is seated in it — the host leaving no
longer ends it outright, since a guest mid-movie shouldn't get cut off just
because the host's connection dropped. It's deleted only once every seat has
been empty for `EMPTY_ROOM_TIMEOUT_MS` (10 minutes) straight, tracked via an
`emptySince` timestamp that's cleared the instant anyone's seated again.
Seat 0 is always the host, assigned at room creation and never reassigned;
guests are seated in join order and stay stable across reconnects because a
returning device presents the `reconnectToken` minted the first time and
reclaims its own seat rather than taking whichever is free. A presented
token that doesn't match its seat (partial local-storage clear, a
regenerated peer id) now falls through to claiming a fresh seat rather than
failing outright — previously that meant a device that only lost its token
was permanently told the room was full even with seats open.

Deliberately ending a room (`POST /rooms/:roomId/close`) is a distinct path
from an accidental disconnect, which still goes through the normal reconnect
grace — so losing power or wifi never silently ends a room out from under a
guest. On a deliberate close, *every* occupied seat gets an explicit
`{"type":"closed"}` frame before its socket closes, not just the host's;
without that, a waiting guest would just see their socket drop, which reads
as a transient failure rather than the deliberate end it was. The
ghost-connection reaper uses `terminate()`, not `close()`, since a
non-responding socket may not be able to complete a graceful close handshake
either — this frees a stuck seat immediately instead of waiting on a
TCP-level timeout that can take minutes or never fire through a hosting
provider's proxy.

### 6.3 Resource limits & security (relay server)

Several real issues were found and fixed in this file:

- **A single malformed message could crash the whole process.** `JSON.parse`
  succeeds without throwing on inputs like the literal text `"null"`; the
  dispatch code that read `msg.type` right after would then throw on a
  null/primitive value, and nothing caught exceptions inside a WebSocket
  message callback — killing every room and every connection on the server,
  not just the offending one. Fixed with an explicit type guard before
  dispatch.
- **The HTTP routes ignored the relay's own auth token.** Only the WebSocket
  upgrade handshake checked `RELAY_TOKEN`; `GET /rooms` (the full room
  directory) and the close endpoint were reachable over plain HTTP with no
  check at all, even on deployments where the token is the default.
- **No caps existed on rooms, connections, or client-supplied string
  lengths** — a single bad actor could create unbounded rooms, or pile
  oversized strings into `chatHistory`/room titles, exhausting memory. This
  is a self-hosted relay for one friend group, not a hardened public
  service, so these limits exist as a backstop against one bad client, not
  because real usage approaches these numbers.
- The close endpoint's request body is now capped before `JSON.parse` runs,
  rather than buffering an arbitrarily large POST first.

The WebSocket upgrade handler uses `noServer: true` plus a manual `upgrade`
listener rather than letting `WebSocket.Server` auto-accept every upgrade:
rejecting a bad token *before* the handshake completes gives a bad client an
immediate HTTP error instead of a connection that gets accepted and then
closed — the latter measured as a ~20-second-delayed, code-1006 disconnect
through the hosting provider's proxy in testing.

### 6.4 Reconnect and backoff (client)

One coroutine owns a connection's whole lifecycle end to end — opening the
session, sending the create/join request, reading frames until the session
ends, gracefully or not — with both outcomes falling through to the same
`finally` block that schedules a reconnect. `retryNow()` (the Lobby's Retry
button) cancels the current attempt and starts a new one immediately, but
coroutine cancellation is asynchronous: the old coroutine's `finally` block
could still run *after* the newer attempt had already connected and taken
over the shared session state, nulling out a connection that just succeeded
and queuing a spurious extra reconnect on top of it. This is guarded by a
monotonic `connectionGeneration` counter — only the attempt that's still the
current generation by the time its `finally` runs is allowed to act. This is
the load-bearing invariant of the whole reconnect path.

`ROOM_FULL` and `ROOM_NOT_FOUND` are treated as terminal rejections, not
transient failures — a reconnect won't fix "the room is full." The client
surfaces whichever specific rejection just happened instead of a generic
"reconnecting," which would misleadingly suggest it's still trying when the
real answer is already known, while still retrying on a timer regardless
(the host could free a seat).

### 6.5 Playback sync state machine

The host owns the authoritative `PlaybackState`; guests reconcile their
local player toward it rather than trusting their own play/pause/seek
history. This replaced an older design where a guest's own buffering could
get broadcast as a false pause — the original source of a "spotty sync"
symptom — which is why `PeerStatus` reports buffering separately from
ready/play intent.

`HostPlaybackCoordinator` and `GuestPlaybackReconciler` are ported down from
a Dart reference implementation (Plezy), keeping the same phase machine and
peer-status-driven stall gating, but deliberately dropping per-media epoch
switching (not needed — each `PlayerScreen` instance here is already scoped
to one movie), RTT-adaptive start delay, and rate-based drift "nudging" —
simplified here to a fixed start delay and hard-seek-only correction, partly
to sidestep ExoPlayer's audio-passthrough/playback-speed interaction, partly
because this app has no variable-speed feature to protect.

A couple of tuning constants have real history behind their current values:
`STALL_GRACE_MS` was widened twice (500 → 1500 → 2500ms) after real-world
testing kept hitting stall/resume cycles that pointed less at "correction
overshoot" and more at one side's connection genuinely not sustaining the
selected transcode bitrate — every buffer event pausing the whole room is
far more visible than a solo client buffering quietly, though a chronically
insufficient bitrate ultimately needs fixing in Settings, not a bigger
number here. The guest-side deadband was widened from an original 350ms
because, without rate-based nudging, hard-seek is the *only* correction
available, and normal WAN clock-sync jitter across a relay-routed,
cross-household connection routinely exceeds a few hundred milliseconds even
once converged — at 350ms that meant a disruptive re-seek (and the rebuffer
it causes) on practically every cooldown cycle.

`intendedPlaying` defaults to `true`, not `false`, because ExoPlayer's own
`playWhenReady` is set `true` at construction time, before the coordinator's
listener is even attached — `onPlayWhenReadyChanged` never fires for a state
change that happened before the listener existed, so defaulting to `false`
meant every session required a manual play press just to get going.

### 6.6 Clock sync

Two independent Android TVs on two different networks have no reason to
agree on wall-clock time; the old sync engine assumed they did (comparing
raw timestamp deltas directly), which is itself a plausible independent
contributor to the original spotty-sync symptom. `ClockSync` runs an
NTP-style offset estimation against the session host instead, keeping a
rolling window of RTT samples and reporting the offset of the *lowest-RTT*
sample, since a single clean exchange beats an average polluted by jittery
ones. `MAX_ACCEPTED_RTT_MS` (5000ms) is set far higher than a
well-connected-network default would use, because this app's real topology —
two households on residential internet routed through a relay hop — makes
round trips regularly exceeding a second normal, not broken; rejecting those
samples meant the offset stayed unresolved forever on a real cross-household
test, silently falling back to assuming zero clock difference, which (if the
system clocks actually differed) would be a permanent, unresolvable "drift"
triggering a hard-seek on every single cooldown cycle forever.

## 7. Plex API integration notes

A number of Plex response-shape quirks were confirmed against a real server
this session and are worth knowing rather than rediscovering:

- `includeReviews=1` is required for the server to attach the `Review[]`
  array; without it, `Review` is simply absent.
- Plex auto-generates a "More with `<lead actor>`" hub only for the
  *top-billed* cast member on `/related` — any other cast/crew member's
  filmography needs a direct `?actor=<id>` query.
- `/hubs/home` (plex.tv's cloud Discover path) 404s against a local Plex
  Media Server; `/hubs/promoted` is the real local-PMS path behind the
  official app's home-screen rows. The suggested/related hub on that
  endpoint only exists when the server has something to offer, so an empty
  result is a valid state, not a bug — its hub identifier isn't confirmed
  stable across server versions, so it's matched defensively by substring.
- A show's own metadata, fetched with `includeOnDeck=1`, embeds the
  in-progress/next-up episode as a nested element — there's no separate
  `/onDeck` sub-resource (confirmed 404).
- An empty `items` array on `fetchMovieDetail` is a *real* response shape
  (a `ratingKey` that's been deleted/moved since it was linked to), not a
  parsing failure — every caller already wraps this call in `runCatching`,
  so the fix here was giving the resulting exception a clear message instead
  of a bare stdlib one.
- Cast/crew headshot URLs come back already-absolute
  (`metadata-static.plex.tv`), unlike most thumb/art fields, which are
  server-relative — prefixing an absolute URL with the server's own base URL
  silently produced a broken image with no crash.
- `/library/recentlyAdded` surfaces TV content at *season* granularity
  ("Season 14"); `parentTitle`/`parentRatingKey` are the actual show's name
  and id, used to route taps to the show's own detail screen since there's
  no season-level detail screen in this app.
- A silent-fallback bug in server selection used to always prefer any
  non-owned (shared) resource, which broke for an account with access to
  more than one shared server while also owning its own — `selectedServerId`,
  once set, is now honored exclusively with no silent fallback to a
  different server.

## 8. Settings persistence

`AppSettings.relays` starts empty with no baked-in placeholder — a hardcoded
default relay doesn't generalize once the app is shared beyond one
household. `RelayEntry.isDefault` picks which relay Watch Together hosts a
new room on; `SettingsStore.save()` normalizes to exactly one flagged entry
(or the first one) regardless of what's passed in, defending against a
caller accidentally producing two defaults. `maxHostSeats` is a client-side
cap sent at room creation — the relay's own `MAX_DEVICE_SEATS` is still the
real ceiling, and lowering it never evicts anyone already in a live room
since a room's seat count is fixed at creation time.

The legacy single-URL → relay-list migration is guarded by a `Mutex`:
`observe()` can have more than one collector (two screens both observing
settings at cold start), and without the lock, two collectors could both see
an empty relay list plus a legacy URL before either write propagated back
through the settings store, each writing their own migrated entry and
leaving duplicate "My relay" rows behind.

## 9. Networking defaults

No caller of the shared `plexHttpClient()` had ever installed `HttpTimeout`
(one separate client, `RelayDirectoryApi`'s, did) — an unresponsive-but-not-
refused Plex server, a real home-server failure mode distinct from
"connection refused," left every suspend call through this client hung
forever with no way for the UI to show a retry state. A 15-second default is
now installed in the shared client itself, generous enough for a slow home
connection or a large library page; individual callers can still override it
(e.g. `PlexResourcesApi`'s own reachability probes use 4 seconds).
`RelayDirectoryApi`'s own 75-second *tolerant* timeout matches the Lobby's
own failure threshold for the same reason: a free-tier relay host that's
been idle needs real time to wake up, and that's treated as normal, not
exceptional.

## 10. KMP portability constraints

A few things in `shared/` are shaped the way they are specifically to stay
portable to a future tvOS target:

- `RelayHttpUrl`/`relayHttpUrl()` hand-roll ws(s)→http(s) URL parsing rather
  than using `java.net.URI`, which isn't available outside the JVM target.
- `SecureTokenStore` is an interface only, with no shared implementation —
  Android and Apple have genuinely different secure-storage models (Android
  hand-rolls AES-GCM via the Keystore; Apple platforms would use the
  Keychain directly, which encrypts at rest with no application-level crypto
  needed), not just different plumbing to the same idea. Each platform's app
  layer provides its own implementation.
- `plexHttpClient()`'s underlying engine is selected automatically per
  platform from whatever Ktor engine artifact is on that target's classpath
  (OkHttp on Android, Darwin on Apple) — callers never choose one
  explicitly.

## 11. Playback pipeline internals (Android)

`ExoPlayerAdapter` is the only implementation of the shared module's
`SyncedPlayer` interface today — it wraps a real ExoPlayer so
`HostPlaybackCoordinator`/`GuestPlaybackReconciler` (both in `shared/`) never
see an ExoPlayer or Media3 type directly. A future tvOS build supplies an
AVPlayer-backed implementation of the same interface instead. `Player`
doesn't key its listeners by anything the caller controls, so the adapter
keeps its own `SyncedPlayerListener -> Player.Listener` map to make
`removeListener` possible.

`PlexPlayerFactory.applySubtitleSelection` applies (or re-applies) subtitle
selection on an already-running player without touching its `MediaItem` —
direct play is one continuous ExoPlayer session, so switching between two
demuxed text tracks (or off) is just a `trackSelectionParameters` update, no
reload needed. Only a burn-required stream, or leaving one, needs a whole
new player/transcode session (see `PlayerScreen`'s `playerIdentity` key).
ExoPlayer doesn't know about Plex stream ids — it only sees whatever text
tracks the container's own extractor demuxes — so steering selection by
language code (rather than mapping a Plex stream id to a `TrackGroup`
index) is the only correlation available without deep format inspection.
Good enough short of two same-language non-forced tracks in one file, a
known limitation Plex clients targeting arbitrary media generally accept.

`buildTranscodeUrl` forces `directPlay=0&directStream=0`, making the server
transcode both video and audio into HLS — also the only way it will burn
image-based subtitles into the video (Plex always hardcodes subtitles during
transcode; there's no separate "burn" flag). `subtitleStreamID` is always
sent explicitly (`0` for "no subtitle" when unset) rather than omitted, so
the server doesn't fall back to its own stored default and silently
reintroduce a track this device didn't ask for.

`TimelineReporter` reports playback progress to `/:/timeline` so a second
account watching the same server (e.g. a cousin's) also sees accurate "Now
Playing"/resume state, matching python-plexapi's `updateTimeline` contract
(`ratingKey`, `key`, `identifier`, `state`, `time`, `duration`).

## 12. Android platform implementations (settings, pairing, token storage)

`AndroidSettings.kt`'s `Context.observableSettings()` is the one genuinely
platform-specific piece of the settings layer: only Android needs a
`Context` to build its underlying key-value store (`SharedPreferences`);
Apple platforms construct `NSUserDefaultsSettings` with no `Context`
equivalent needed. It's a lightweight per-call wrapper — `SharedPreferences`
instances are already memoized per file name by Android, so there's nothing
here that needs its own memoization, mirroring how DataStore's
`preferencesDataStore` delegate was used pre-migration. `AndroidTokenStore`
keeps its own separate DataStore (`plex_token`) for the encrypted blob + IV,
so `Context.tokenStore` takes the `Context` directly rather than routing
through `observableSettings()`.

`AndroidTokenStore` hand-rolls what `androidx.security:security-crypto`
(`EncryptedSharedPreferences`, deprecated in 2025) used to provide: an
AES-GCM key that never leaves hardware (or a software fallback on older
devices), via the Android Keystore directly, encrypting the Plex account
token before it's persisted in DataStore.

`loadToken()` catches `GeneralSecurityException` around the decrypt call and
treats it as "no token" (clearing the stored ciphertext) rather than letting
it propagate — a mismatched key (the alias changed, or the OS invalidated
the Keystore entry, e.g. after a factory reset restore) throws
`AEADBadTagException` from GCM's tag-verification step, which otherwise
crashes the app on every launch with no way to recover short of clearing app
data manually. Falling through to a normal logged-out state just means one
extra Plex re-login instead.

`PairingServer` is a tiny, hand-rolled, LAN-only HTTP server — the whole
surface needed is exactly two routes (serve a form, accept its POST), so a
real server dependency would be overkill. It lets a phone on the same Wi-Fi
"paste" a relay's nickname + URL into the TV's Settings screen without
typing on a remote, the closest local-only analog to Plex's own PIN-link
flow. Per design spec 09d, it's invoked fresh per relay-add — one
`PairingServer` instance per attempt, nothing here is a singleton, so
supporting a second/third relay later needed no lifecycle change, just a
second form field. Its per-session random path segment (`token`, not just
`/`) avoids a stray request from something else on the LAN (or a
port-scanner) landing on the form by accident. `start()` returns the
URL to show/QR-encode, or `null` if no LAN IPv4 address could be found (the
TV isn't actually connected to a network). The served page's dark
background/two-tone NeonPurple styling matches `AppColors.kt` so it reads as
part of the same app even though it's a plain HTTP page, not Compose.
