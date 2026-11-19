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

Open — design decisions:

- [ ] **Home's hero Resume opens the page** rather than resuming, so it
  takes two presses. Deliberate (home_hero.dart), but labelled like play.
- [ ] **Watchlist removal asks to confirm** (long-press → "Remove … from
  your watchlist?"). DESIGN.md #12 says act at once with an 8 s undo chip.
- [ ] **The room dialog's Phone chat toggle does nothing** (disclosed in
  watch_together_start_screen.dart). Wire it (open the Chat QR in the
  lobby?) or drop it.
- [ ] **Lobby's "Close the room" only parks it** for 3 minutes (same as
  Back). Rename, or make it end the room (confirm if anyone has joined).
- [ ] **Joining late lands in the lobby** with "Start for everyone" while
  the host is already watching; going straight into the player at the
  room's spot may be better.
- [ ] **A show page opens with its title cut in half** at the top edge
  (focus on the next episode scrolls the header partly away).
- [ ] **Copy:** "guests will sync within a frame" overclaims; the bar says
  "End" and its confirm "End the session?" while everywhere else says
  "room"; Search's no-results line has no instruction.
- [ ] **The selected-and-focused dot** crowds short labels (Movies' Titles
  tab, the player menu's Subtitles tab).
