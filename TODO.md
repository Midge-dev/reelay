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

- [ ] **Plex burn-in 400s.** Choosing an embedded subtitle on Plex (e.g. 300)
  offers only "(transcode)", and PMS rejects the transcode with a 400. Next:
  replay the `start.m3u8` URL with curl to read PMS's reason, then try the
  `/video/:/transcode/universal/decision` call first (plezy does).
- [ ] **Quality cap doesn't force a transcode.** `decidePlayback` only
  transcodes for burn-in or a failed direct play, so picking 2 Mbps on a
  4 Mbps file still direct-plays. Decide whether a cap below the file's
  bitrate should transcode.
- [ ] **Relay settings rows are skipped by Up/Down** — their buttons sit far
  right, so vertical moves from "‹ Settings" / "Add a relay" jump past them.
  Only Right reaches them.
- [ ] **The player stays on the last frame** at the end of a movie instead
  of closing.
