# Reelay — Project Notes

Custom Android TV Plex client for the Nvidia Shield Pro (2019), built to enable
real synchronized "watch together" playback with a cousin on a remote Plex
server. See the full architecture/phase plan for context; this file tracks
running setup details, decisions, and gotchas as we build.

> **2026-09-20:** the app was rewritten in Flutter (`flutter/`) and the
> original Kotlin/Compose implementation retired. **"Target device" below is
> still accurate** (same physical Shield, same ADB workflow). Everything
> from "Toolchain" onward describes the retired Kotlin/Gradle/Compose stack
> specifically and is kept only as historical record — see `flutter/README.md`
> and `flutter/pubspec.yaml` for the current toolchain.

## Target device

- Nvidia Shield Pro (2019), model `SHIELD_Android_TV`, codename `mdarcy`
- Runs up to Android 11 — app's `minSdk = 26` comfortably covers this
- On the home WLAN at `192.168.0.81` (found by MAC vendor lookup: Nvidia
  Corporation OUI `3c:6d:66`, since the Shield doesn't have a fixed/known IP
  ahead of time)
- ADB over network: enabled via Settings → Device Preferences → Developer
  options → Network debugging. Connect with:
  ```
  adb connect 192.168.0.81:5555
  ```
  (accept the on-device RSA key prompt the first time)

## Toolchain

- No Android Studio GUI installed — driving everything via CLI (Claude Code),
  so only the command-line SDK tools were installed, not the full IDE.
- Android SDK root: `~/android-sdk` (`ANDROID_HOME`/`ANDROID_SDK_ROOT`, added
  to `~/.bashrc` along with `cmdline-tools/latest/bin` and `platform-tools`
  on `PATH`)
- Java: system OpenJDK 21 (already present, no install needed)
- Gradle: wrapped at **9.4.1** — note AGP 9.2.0 actually requires Gradle
  9.4.1+ despite some docs/search results suggesting 8.11 was enough; trust
  the Gradle error message's stated minimum over secondary sources here.
- AGP: **9.2.0**, using AGP 9's new *built-in Kotlin support* — no
  `org.jetbrains.kotlin.android` plugin applied, just `com.android.application`
  + `org.jetbrains.kotlin.plugin.compose` for the Compose compiler.
- Kotlin: 2.4.10
- compileSdk/targetSdk: **36** (bumped up from an initial 35 because
  `androidx.media3:*:1.10.1` requires compiling against API 36+)
- UI: Jetpack Compose for TV (`androidx.tv:tv-material:1.1.0`,
  `tv-foundation:1.0.0`) — chosen over the older Leanback library as the
  current Google-recommended path and a much gentler on-ramp coming from
  web/React.
- Playback: Media3 ExoPlayer `1.10.1`.

## Repo layout

- `app/` — the Android TV Kotlin/Compose client
- `relay/` — (Phase E) the watch-together WebSocket relay, Node.js
- App name: **Reelay**; package/applicationId: `com.reelay.tv`

## Decisions made along the way

- **Forking existing open-source clients was considered and ruled out.**
  Plex's own "Watch Together" feature is being sunset, so not worth building
  on top of. Plezy (Flutter, open source) doesn't support transcoding, which
  is a hard requirement here (subtitle burn-in for image-based subs relies on
  it). Building custom, per the original plan.
- Cousin will run this same app on their own Android TV device/account,
  pointed at the same relay server — keeps the watch-together sync protocol
  symmetric (no need to reverse-engineer Plex's own Companion/Remote-Control
  protocol to drive an unmodified official client).
- Relay hosting: Render.com free tier (Fly.io's free tier no longer exists as
  of 2026).

## Gotchas hit so far

- Running `gradle wrapper` from the wrong working directory (e.g. `cd /tmp &&
  ... gradle wrapper` in one chained command) silently generates the wrapper
  in the wrong place with a confusing "directory does not contain a Gradle
  build" error — always pass `-p <project dir>` explicitly or `cd` in its own
  step first.
- `android:banner` and launcher icon don't require raster PNGs — plain
  `VectorDrawable`s work fine as placeholders (`app/src/main/res/drawable/tv_banner.xml`,
  `ic_launcher_background.xml` / `ic_launcher_foreground.xml`). Swap for real
  artwork later.
- (Fixed 2026-08-17) Every reinstall used to force a fresh Plex login + relay
  re-pair. Cause: no shared debug keystore, so AGP fell back to each
  environment's own implicit `~/.android/debug.keystore` — stable on one
  machine, but the GitHub Actions runner has none persisted, so CI minted a
  new random one on every run. Installing a differently-signed APK over an
  existing one forces `adb` to uninstall (wiping app data) before it'll
  reinstall. Fixed by checking `app/debug.keystore` into the repo and
  pointing `signingConfigs.debug` at it explicitly (see `app/build.gradle.kts`)
  — every build, local or CI, now signs identically, so `adb install -r`
  just updates in place. This keystore must stay in the repo and never get
  regenerated, or the whole class of problem comes back.

## Material 3 component audit (2026-08-17)

Goal: use Material 3 components everywhere possible. Scanned every `import`
across `app/src/main/java` for non-M3 UI. Findings below.

**Non-M3 imports: none found**, except one deliberate, already-approved
exception — `ui/common/AppLoadingIndicator.kt` pulls `ContainedLoadingIndicator`
from the base (non-TV) `androidx.compose.material3` library, pinned to
`1.5.0-alpha18` (see `libs.versions.toml` for why that exact version), because
tv-material3 has no loading indicator of any kind. Every other screen is
`androidx.tv.material3` only. `androidx.compose.material.icons.*` shows up
everywhere too, but that's just the icon pack (no TV-specific equivalent
exists, and it isn't a "component" in the same sense).

**tv-material3 component families currently in use:** Button/OutlinedButton,
Card/StandardCardContainer, FilterChip, Icon, ListItem, ModalNavigationDrawer/
NavigationDrawerItem, RadioButton, Surface, Switch, Text.

**tv-material3 component families available (1.1.0) but never used:**
Carousel, Checkbox, IconButton, Tab/TabRow, WideButton. Worth a look before
building anything new by hand — e.g. `IconButton` might be a cleaner base for
one-off icon-only actions than a bare `Icon` + `.clickable`, `Carousel` could
replace a hand-rolled hero rotator if one ever gets built.

**Hand-rolled UI that exists because tv-material3 has *no* equivalent at
all** (confirmed by listing every top-level composable in the 1.1.0 aar —
this isn't a case of skipping an available component):
- `ui/common/NeonScrollbar.kt` — custom `Canvas`-drawn scrollbar; tv-material3
  ships no scrollbar/scrollbar-indicator of any kind.
- `ui/common/KeyboardOnSelect.kt` (`ClickToTypeTextField`) — wraps Compose
  Foundation's `BasicTextField`; tv-material3 has no `TextField`.
- `ui/common/ChatOverlay.kt` — toast-style fading message list; no
  Snackbar/toast component in tv-material3.
- `ui/player/PlayerScreen.kt`'s `SubtitleMenu` and `ui/home/HomeScreen.kt`'s
  `RemoveConfirmOverlay` — custom `Column`/`Box` panels standing in for a
  dialog; tv-material3 has no Dialog/BottomSheet/ModalDrawer-as-dialog
  component (`ModalNavigationDrawer` is navigation-specific, not a general
  dialog).
- `ui/home/HomeScreen.kt`'s `ContinueWatchingPoster` — hand-rolled
  `Box.combinedClickable` instead of `Card`, specifically because `Card` has
  no `onLongClick` (needed for the remove gesture) — confirmed by decompiling
  the library; not a stylistic choice.

None of the above are fixable by swapping to a tv-material3 component that
was overlooked — closing these would mean either pulling more pieces from
the base (non-TV) `androidx.compose.material3` library (same move as the
loading indicator) or accepting the hand-rolled versions as permanent. Real
migration opportunities are the five unused-but-available families above.
