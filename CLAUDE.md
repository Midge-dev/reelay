# Reelay

Plex/Jellyfin client for a 10-foot display, driven by a D-pad remote. Flutter
app under `flutter/lib/`, targeting Android TV today (Apple TV planned).

## Before any UI work

Read **[`DESIGN.md`](DESIGN.md)** first, every time — it's the non-negotiable
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
  media segments.
- `test/journeys/ux_tour_test.dart` — not a test: `UX_TOUR=1 flutter test
  test/journeys/ux_tour_test.dart` screenshots every screen in the app's
  own type into `build/journey_shots/` (`UX_SCALE=1.5` for another UI size),
  for a design pass against DESIGN.md.
- `test/screens/player/player_playback_test.dart` — playback and subtitles
  on Plex and Jellyfin.
- `test/sync/` — Watch Together rooms in simulation, plus a fuzzer (see
  ARCHITECTURE.md §2.7).

Target device and ADB connection details are in `NOTES.md`.

## Repo layout

- `flutter/lib/` — the app
- `ARCHITECTURE.md` — why the sync, relay and Plex code work the way they do
- `relay/` — the watch-together WebSocket relay (Node.js)
- `docs/tokens.json` — canonical Nocturne token values
- `docs/focus-navigation-qa-checklist.md` — regression checklist for D-pad/focus work
