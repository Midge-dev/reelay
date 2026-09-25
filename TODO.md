# Reelay — To do

- [ ] **Write more fun loading messages.** Add lines in the same `'Text…',`
  format to either list (one is picked at random each time):
  - `flutter/lib/screens/common/loading_screen.dart` — `_flavorMessages`,
    the main loading screen (12 messages today).
  - `flutter/lib/screens/onboarding/setup_ready_screen.dart` — `_flavor`,
    the last step of first-run setup (4 messages, all repeats of the main
    list). Optionally merge the two into one shared list.

- [ ] **Set up a Jellyfin test server** (needed before Jellyfin Phases 1–5 can
  be checked live; branch `reelay-jellyfin-support`). No account to sign up
  for — the server is self-hosted and its first-run wizard creates the user
  Reelay signs in with.
  - Server: Docker `jellyfin/jellyfin` on the Mac, port 8096, config + media
    under `~/jellyfin-test/` (delete the folder and container to undo). The
    Shield reaches it at the Mac's LAN address.
  - Movies: the Blender open films (Big Buck Bunny, Sintel, Tears of Steel —
    Creative Commons), in `Title (Year)/Title (Year).mkv` folders.
  - Shows: a small fake two-season show from short clips,
    `Show (Year)/Season 01/Show S01E01.mkv`, so seasons, Next Up and
    Continue Watching have something to show.
  - Player edge cases, made with ffmpeg: H.264 and HEVC 10-bit; AAC and AC3
    5.1; two audio tracks; embedded, PGS, SRT-sidecar and ASS-sidecar
    subtitles; a 23.976 fps file for frame-rate matching.
  - Cross-backend fold: put the same Big Buck Bunny file in a Plex library
    too, to check a Plex copy and a Jellyfin copy fold into one card.
  - Then: run the wizard in a browser (create the user, add Movies and
    Shows), and do the on-device Phase 0 check of the Plex path on the
    Shield (profile build keeps the sign-in).
- [ ] **Jellyfin decisions still open:** watchlist on Jellyfin-only profiles
  (hide / map to Favorites / Plex-only); Quick Connect on O3 (Link
  Jellyfin) as a third path?
