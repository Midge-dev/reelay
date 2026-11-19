# Reelay — To do

- [ ] **Write more fun loading messages.** Add lines in the same `'Text…',`
  format to either list (one is picked at random each time):
  - `flutter/lib/screens/common/loading_screen.dart` — `_flavorMessages`,
    the main loading screen (12 messages today).
  - `flutter/lib/screens/onboarding/setup_ready_screen.dart` — `_flavor`,
    the last step of first-run setup (4 messages, all repeats of the main
    list). Optionally merge the two into one shared list.

- [x] **Set up a Jellyfin test server.** Docker `jellyfin/jellyfin` on the
  Mac, port 8096, config + media under `~/jellyfin-test/` (server
  GRIM-TEST). Movies, a two-season test show, the ffmpeg edge-case clips
  (plus a VobSub "Bitmap Subtitles" clip for burn-in) and a Plex copy of
  Big Buck Bunny for the fold check.
- [x] **Jellyfin decisions:** Favorites stand in for the watchlist; Quick
  Connect is a sign-in path on O3.

## Jellyfin follow-ups (branch `reelay-jellyfin-support`, all six phases done)

- [ ] **Redeploy the live relay** with this branch's `relay/server.js` (or
  merge to `main`, which Render builds from). Until then a Jellyfin-only
  guest can't find a Plex host's title on the real relay. Older app builds
  keep working against the new relay.
- [ ] **Watch Together, Plex host → Jellyfin-only guest** on two devices.
  The other direction passed on the test relay (`reelay-sync-test` on
  Render); this one is covered by unit tests only.
- [ ] **Collections tab is empty on Jellyfin libraries.** Jellyfin keeps
  collections (BoxSets) in their own view, not under a library, so
  `JellyfinClient.fetchCollections` returns nothing. Opening one works.
- [ ] **Next-episode cards can't be removed from Continue Watching** on
  Jellyfin — they have no position to clear and Jellyfin has no "hide".
  Part-watched titles remove fine.
- [ ] **Watchlist as two labeled rows** (Plex Watchlist + Jellyfin
  Favorites) once the design is mocked; today they're one merged list.
- [ ] **No reviews on Jellyfin titles** — Jellyfin doesn't keep them. Decide
  whether the section hides or shows something else.

## Found while testing

- [ ] **Plex burn-in 400s — fix to try on the Shield.** The first transcode
  opens fine; switching subtitles mid-film (a restart) 400'd on ScreamTiki.
  Branch `fix-watch-together-seek-loop` now reuses one transcode `session`
  per playback (it used to start a second transcode beside the still-running
  first), asks `/decision` first and puts Plex's reason on the error screen,
  stops the transcode on leaving/going back to direct play, and no longer
  sends the ignored `subtitleStreamID`. If it still fails, the error screen
  and `adb logcat -s flutter | grep '\[playback\]'` say why. Not yet tried:
  dropping `offset=` and seeking in-stream as plezy does.
- [ ] **Quality cap doesn't force a transcode.** `decidePlayback` only
  transcodes for burn-in or a failed direct play, so picking 2 Mbps on a
  4 Mbps file still direct-plays. Decide whether a cap below the file's
  bitrate should transcode.
- [ ] **Relay settings rows are skipped by Up/Down** — their buttons sit far
  right, so vertical moves from "‹ Settings" / "Add a relay" jump past them.
  Only Right reaches them.
- [x] **The player stays on the last frame** at the end of a movie instead
  of closing. (Fixed on `qa-journeys-ux-polish`: it reports the end, which
  marks the title watched, and leaves; an episode with Up Next goes on.)
- [x] **A "Next episode" button in the player** (done on
  `fix-watch-together-seek-loop`; works in rooms — see ARCHITECTURE.md
  §2.5) for anything with episodes,
  so you can skip on whenever you like, not only from the Up Next card in
  the last 40 s. PlayerScreen already has the pieces (`loadNextEpisode`,
  `onPlayNext`); it needs a button in the controls row (only when there is a
  next episode), its D-pad place in the row, and in Watch Together, what a
  guest pressing it does (likely: only the host can, or it asks the host).

## From the 2026-11-19 QA pass (branch `qa-journeys-ux-polish`)

Fixed there, each with a journey: the Watch Together bar on Home was
skipped by Up/Down; its End confirm was drawn inside the bar; a late
joiner's lobby seated the host twice; a guest stayed in the player after
the host ended the room, and saw "In sync" after the host's TV went off;
Jellyfin-only profiles were called "You" in rooms; error screens were a
bare line with nothing to focus; the room dialog offered Resume on titles
never started; the player's main buttons had no accessible names; the
Settings version line ran onto the screen's edge.

Decided and done (same branch, 2026-11-19), each with a journey or test:

- [x] Home's hero Resume plays straight away (cards still open the page).
- [x] Removing from Home's watchlist row or Continue Watching acts at once
  with an 8 s undo chip (Back undoes, Up reaches it); the server hears when
  it runs out or you leave Home. RemoveConfirmOverlay is gone.
- [x] Phone chat is a setting (Settings → Watch Together). On: the lobby
  shows the QR, the player keeps its QR button. Off: neither. The room
  dialog's dead toggle is gone.
- [x] The lobby's "Close the room" ends the room (asks first if anyone has
  joined); Back still keeps it open for 3 minutes.
- [x] Joining a room that's already playing goes straight into the player;
  the room holds ("Catching up with the room") until you've opened, then
  plays on by itself.
- [x] A show page opens on its Play button, header whole.
- [x] Copy: "guests stay in sync"; "End room" / "End the room?"; Search's
  no-results line says what to try. "Narrow this library" is gone.
- [x] No selected-and-focused dot on segmented tabs and filter chips.
- [x] The rail's Watch Together item gets a dot when a room you haven't
  seen opens (seen = on Home's bar or in the rooms panel).

Still open:

- [ ] **Slow settles in the sync fuzzer:** 2 of 1000 rooms (seeds 447,
  600) take over 30 s — a guest sits ~1 s off the host until a late
  correction. Was 4 of 1000 before the late-joiner change. Same class as
  the known drift follow-up (rate-nudging).
- [ ] **The undo chip doesn't animate the hold** (the handoff's 4% draw-in
  and desaturate over the 600 ms hold).
