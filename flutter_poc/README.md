# Reelay Focus POC

A small, isolated Flutter project (Android-only) built to answer one
question: can a hand-rolled Flutter D-pad/focus system pass the same
real-device checks the current Compose implementation already passes? See
`../docs/focus-navigation-qa-checklist.md` for the checklist this is being
tested against, and `../ARCHITECTURE.md` §4 for the Compose-side context.

This is throwaway research code on the `flutter-reelay` branch — not part of
the shipping app, no Plex/relay integration, all data is mocked.

## Running on the real device (D-pad/focus behavior testing)

This is the only way to actually verify focus/D-pad behavior — see
checklist rule #0 for why (arrow keys on a keyboard/mouse taps are not a
reliable stand-in for real remote input).

```
cd flutter_poc
flutter build apk --debug
adb -s 192.168.0.81:5555 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 192.168.0.81:5555 shell am start -n com.reelay.reelay_focus_poc/com.reelay.reelay_focus_poc.MainActivity
```

Then drive it with real key events, not taps:

```
adb -s 192.168.0.81:5555 shell input keyevent KEYCODE_DPAD_UP/DOWN/LEFT/RIGHT/CENTER
adb -s 192.168.0.81:5555 shell input keyevent --longpress KEYCODE_DPAD_CENTER
```

## Running on this Mac (styling/layout iteration only)

For visual/layout changes only — colors, spacing, sizing, animation curves.
**Do not use this to verify focus/D-pad behavior itself** — arrow keys on a
Mac keyboard exercise the same underlying Flutter focus-traversal system so
basic navigation looks right, but timing-sensitive things (the long-press
detector, real-remote event quirks) can't be trusted here.

In a separate terminal, from the repo root:

```
cd flutter_poc
flutter run -d macos
```

First launch takes 30-90s to build. Once it's running, a real macOS window
opens and arrow keys act as the D-pad. While that terminal is attached:

- `r` — hot reload. Applies most code edits almost instantly without
  restarting the app or losing its current state.
- `R` — hot restart. Use this if a change to `r` doesn't seem to take
  effect (usually because it changed a widget's structural shape, not just
  a value inside an existing one).
- `q` — quit.

If it's not already enabled on this machine, `flutter create --platforms=macos .`
(run once from `flutter_poc/`) adds macOS desktop support to an
Android-only project without touching existing files.
