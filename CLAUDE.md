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

Target device and ADB connection details are in `NOTES.md`.

## Repo layout

- `flutter/lib/` — the app
- `ARCHITECTURE.md` — why the sync, relay and Plex code work the way they do
- `relay/` — the watch-together WebSocket relay (Node.js)
- `docs/tokens.json` — canonical Nocturne token values
- `docs/focus-navigation-qa-checklist.md` — regression checklist for D-pad/focus work
