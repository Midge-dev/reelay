# Reelay (Flutter)

This is the real app, being built incrementally per the phased conversion
plan (`/Users/midge/.claude/plans/concurrent-moseying-squirrel.md` at time
of writing — ask if that path has moved). It replaces the Kotlin/Compose
app in `../app/` + `../shared/` once it reaches parity; see that plan's
Phase 6 for the cutover conditions. Unlike `../flutter_poc/` (throwaway
research code, not meant to be merged), this project is meant to ship.

`applicationId` is `com.reelay.tv.dev` — deliberately distinct from the
production Kotlin app's `com.reelay.tv` so both can be installed on the
same Shield at once during development. This only changes at cutover.

## Working practice: fast loop first, then the Shield

Iterate on logic/styling fast via the macOS desktop target — no D-pad
needed for pure layout/animation work:

```
cd flutter
flutter run -d macos
```

`r` hot-reloads, `R` hot-restarts (use this if a change to `r` doesn't
seem to take effect — usually means the edit changed a widget's structural
shape, not just a value inside an existing one), `q` quits.

**This is not valid for verifying focus/D-pad behavior.** Arrow keys on a
Mac keyboard exercise the same underlying Flutter focus-traversal system,
so basic navigation *looks* right, but real-remote quirks (long-press
timing, actual key-event sequencing) can't be trusted here — see
`../docs/focus-navigation-qa-checklist.md` rule #0. Any screen/component
that touches focus needs a real pass on the Shield before it's considered
done:

```
cd flutter
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.reelay.tv.dev/com.reelay.tv.dev.MainActivity
adb shell input keyevent KEYCODE_DPAD_UP   # etc — never `adb shell input tap`
```

## What's ported so far

- `lib/theme/` — colors, spacing, shape, typography, motion, and the
  focus/glow treatment tokens, ported directly from `../docs/design-tokens.md`.
- `lib/state/app_state.dart` — the sealed `AppState` hierarchy, a direct
  port of `MainActivity.kt`'s single hand-rolled navigation state (no
  `go_router`/named routes — deliberately matches the Kotlin app's existing
  manual back-stack model instead of introducing a new one).
- `lib/screens/app_root.dart` — renders whichever `AppState` is current;
  every case is a `PlaceholderScreen` until Phase 4 lands the real ones.

Data layer (Plex client, settings, secure token storage) and the
watch-together sync engine are not started yet — see the plan's Phase 1/2.
