# Reelay

Plex/Jellyfin client for a 10-foot display, driven by a D-pad remote. Flutter
app under `flutter/lib/`, targeting Android TV today (Apple TV planned).

## Before any UI work

Read **[`docs/DESIGN.md`](../docs/DESIGN.md)** first, every time — it's the non-negotiable
rules for the **Nocturne** design system (focus signal, motion budget, scrim
policy, scale factor, copy rules) and is short on purpose. Exact values are in
`docs/tokens.json`; the Dart ports are `flutter/lib/theme/tokens.dart` and
`flutter/lib/theme/typography.dart`. Every focusable component routes through
`flutter/lib/kit/focusable_surface.dart` — never hand-roll a focus treatment
in a screen file.

The full design handoff (HTML references with per-screen intent notes, plus
the handoff README) lives in `design_handoff_reelay_nocturne/` at the
workspace root (sibling to this repo, not inside it).

## Testing

Fast loop for logic/layout — no D-pad needed:

```
cd flutter && flutter run -d macos
```

Arrow keys exercise Flutter's focus-traversal system but **cannot** verify
real D-pad behavior (long-press timing, real key-event sequencing — see
`docs/focus-navigation-qa-checklist.md` rule #0). Any change touching focus
needs a real pass on the Shield:

```
cd flutter
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.reelay.tv/com.reelay.reelay.MainActivity
adb shell input keyevent KEYCODE_DPAD_UP   # etc — never `adb shell input tap`
```

`com.reelay.tv` is the applicationId (changed from `com.reelay.tv.dev` at the 2026-09-20 production
cutover); `com.reelay.reelay.MainActivity` is Flutter's Android embedding under
`android/app/src/main/kotlin/`, which intentionally doesn't match the applicationId — see the
comment in `android/app/build.gradle.kts`.

Before the Shield pass, the automated layers catch most of it (run with
`flutter test`):

- `test/journeys/` — the whole real app against a fake Jellyfin server,
  driven with D-pad/Select/Back on the Shield's 960×540 canvas. Every press
  checks something visible has focus. `remote_journeys_test.dart` walks
  real flows (open, Back, remove, panels, errors);
  `focus_crawl_test.dart` random-walks every screen at 100/130/150% UI
  size, failing on hidden or faded-out focus, dead ends and overflows.
  `watch_together_journeys_test.dart` hosts and joins rooms through the
  real screens against an in-process relay (`harness/fake_relay.dart`)
  with a friend on another TV (the real relay client and sync logic);
  `playback_journeys_test.dart` checks resume, progress reports and the
  end of a film as the server sees them; `skip_markers_journeys_test.dart`
  covers Skip intro and Up Next at the credits, from the fake server's
  media segments; `row_journeys_test.dart` walks every horizontal row
  (`harness/rows.dart`) against docs/DESIGN.md's row rules — whole,
  unclipped focus, a row that holds still until focus goes past its edge
  and then moves just far enough, a flush end, and a held key that keeps up
  and settles. A new row belongs there. `grid_journeys_test.dart` does the
  same for every poster grid (`harness/grids.dart`): straight down, the
  next row peeking, back up clear of the top fade, a held Down that keeps up.
  `player_journeys_test.dart` drives the player by remote: the control row
  end to end, the scrubber as a focus target, auto-hide, and the menu panel
  (screens 13 and 14).
  `setup_journeys_test.dart` runs first-run setup (O1–O5) by remote,
  Jellyfin-only, typed on the TV (`Journey.type` stands in for the TV's
  keyboard) — with `realFonts: true`, as layout-heavy pages need: the test
  font's wide glyphs wrap them off screen.
- `test/journeys/ux_tour_test.dart` — not a test: `UX_TOUR=1 flutter test
  test/journeys/ux_tour_test.dart` screenshots every screen in the app's
  own type into `build/journey_shots/` (`UX_SCALE=1.5` for another UI size),
  for a design pass against docs/DESIGN.md.
- `test/screens/player/player_playback_test.dart` — playback and subtitles
  on Plex and Jellyfin.
- `test/sync/` — Watch Together rooms in simulation, plus a fuzzer (see
  docs/ARCHITECTURE.md §2.7).

Target device and ADB connection details are in `NOTES.md` at the repo root —
local only (gitignored), like `TODO.md`, the working to-do list.

## Repo layout

- `flutter/lib/` — the app
- `docs/ARCHITECTURE.md` — why the sync, relay and Plex code work the way they do
- `docs/DESIGN.md` — the Nocturne UI rules
- `relay/` — the watch-together WebSocket relay (Node.js)
- `docs/tokens.json` — canonical Nocturne token values
- `docs/focus-navigation-qa-checklist.md` — regression checklist for D-pad/focus work
