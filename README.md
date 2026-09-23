# Reelay

A custom Android TV Plex client with real synchronized "watch together"
playback — built for two people on separate Plex accounts/servers/houses to
watch the same movie in sync. Not on the Play Store; installed by sideloading
the APK. See `ARCHITECTURE.md` for how it works and `NOTES.md` for setup
details.

## Building from source (for developers)

**Most people don't need this section** — a prebuilt APK is published
automatically on every push, see
[Installing the app](#installing-the-app-for-whoever-is-joining-you) below.
This section is only for making your own changes to the code.

The app (`flutter/`) is a Flutter project targeting Android TV.

### Prerequisites

- **Git**
- **Flutter SDK** (stable channel) — [install instructions](https://docs.flutter.dev/get-started/install).
  Developed against Flutter 3.47.4; run `flutter doctor` after installing to
  confirm your setup.
- **Android SDK command-line tools** — `flutter doctor` will tell you if
  these are missing and how to get them via `sdkmanager`; the full Android
  Studio GUI isn't required.
- **JDK 17+** — any distro's OpenJDK works. Check with `java -version`.

### Clone and build

```
git clone https://github.com/Midge-dev/reelay.git
cd reelay/flutter
flutter pub get
flutter build apk --debug
```

The first run will download dependencies, so expect it to take a few
minutes. If `flutter doctor` flags a missing Android SDK, point Flutter at
yours via `flutter config --android-sdk-root <path>`.

Once it finishes, the debug APK is at:

```
flutter/build/app/outputs/flutter-apk/app-debug.apk
```

The Settings screen falls back to a placeholder LAN address until you set a
real relay URL — every install configures its own, either by typing it in
Settings or with the "Pair from phone" button there (see
[Settings — relay URL](#settings--relay-url) below).

That's the file you sideload — see below. (A release build,
`flutter build apk --release`, works too, but is signed with the debug key
unless you have the real release keystore — `flutter/android/key.properties`
+ `flutter/android/app/release.keystore`, both gitignored and never
committed — so it installs fine, it just won't match an existing
release-signed install on-device.)

## Installing the app (for whoever's joining you)

### What you need

- An Android TV device (e.g. an Nvidia Shield) on the same Wi-Fi as whatever
  you're using to get the APK onto it.
- A Plex.tv account that the host has shared their library with (Plex
  Friends) — accept that invite first if you haven't.
- The relay URL (and token, if any) from the host — looks like
  `wss://reelay-sync.onrender.com?token=...`. You'll need this for the
  Settings screen once the app's installed.

### Option A — Downloader app (easiest, no computer needed)

Every push to `main` automatically builds a fresh APK and publishes it as a
direct download here:

```
https://github.com/Midge-dev/reelay/releases/latest/download/reelay.apk
```

1. On the Android TV, install **Downloader** from the app store.
2. Open Downloader and paste in the link above.
3. Let it download, then install. You'll be prompted to allow installs from
   Downloader the first time — accept that.

### Option B — adb sideload (if you're comfortable with a terminal, or the
host can walk you through it / remote in)

1. On the TV: Settings → Device Preferences → About → click **Build** 7
   times to unlock Developer Options.
2. Developer Options → **Network debugging** → on. Note the IP address shown
   on screen.
3. From a computer with `adb`, grab the APK (either download it from
   [the latest release](https://github.com/Midge-dev/reelay/releases/latest/download/reelay.apk),
   or build it yourself per the section above) and install it:
   ```
   adb connect <tv-ip-address>:5555
   adb install reelay.apk
   ```
4. Accept the connection prompt that appears on the TV.

### First launch

1. Open **Reelay** from the apps list.
2. It shows a short code and `plex.tv/link`. On your phone or any browser,
   go to that address and enter the code.
3. Once logged in, you should see the host's shared library.

### Settings — library source

If your Plex account can see more than one server (e.g. you're a Friend on
someone else's library too, not just the host's), open **Settings** →
**Available sources** and pick the host's server explicitly — otherwise the
app falls back to a guess that isn't always right, and you'd end up browsing
the wrong (or an incomplete) library. If you only have access to one server,
there's nothing to do here.

### Settings — relay URL

Every install needs its own relay URL entered once — nothing is baked into
the APK. From the library screen, open **Settings**, then either:

- **Pair from phone (easiest)** — press **Pair from phone**. A QR code and a
  URL appear. Scan it with your phone (it needs to be on the **same Wi-Fi**
  as the TV), which opens a small page where you paste the relay URL and hit
  send — it fills in the Settings field on the TV automatically. No typing
  on the TV remote.
- **Type it manually** — select the **Relay URL** field and enter it
  directly (include `?token=...` on the end if the relay requires one).

Then **Save**.

### Watching together

1. Both of you open the **same title** from your library.
2. Press Play at roughly the same time. The app finds the other person's
   session over the relay automatically and keeps playback in sync —
   pause/play/seek on either end propagates to the other.
3. The player shows "Sync: connecting…" briefly in the top-right, then it
   disappears once connected. If it says "reconnecting…" for a while, double
   check the relay URL/token in Settings.

## Deploying the relay (for the host)

The relay (`relay/`) needs to be reachable from both devices over the
internet — deployed to Render.com's free tier.

1. Push this repo to GitHub (already done, if you're reading this from it).
2. On [render.com](https://render.com), **New → Blueprint**, point it at
   this repo. It picks up `relay/render.yaml` automatically — a free-tier
   Node web service with a random `RELAY_TOKEN` generated for you.
3. Render gives you a URL like `https://reelay-sync.onrender.com` — the
   app needs the WebSocket form: `wss://reelay-sync.onrender.com`.
4. Grab the generated `RELAY_TOKEN` from the service's **Environment** tab
   and share both the URL and token with whoever's joining you (they append
   `?token=<token>` to the relay URL in their own Settings screen).
5. Free-tier Render services spin down after inactivity and take a few
   seconds to wake up on the first connection of a session — expect the
   first "Sync: connecting…" to take a little longer than usual.
