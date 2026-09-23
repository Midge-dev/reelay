# Reelay — Project Notes

Custom Android TV Plex client for the Nvidia Shield Pro (2019), built for
real synchronized "watch together" playback with a cousin on a remote Plex
server. This file tracks setup details and decisions; the reasoning behind
the sync and Plex code is in `ARCHITECTURE.md`, the UI rules in `DESIGN.md`.

## Target device

- Nvidia Shield Pro (2019), model `SHIELD_Android_TV`, codename `mdarcy`,
  Android 11
- On the home WLAN at `192.168.0.81` (found by MAC vendor lookup: Nvidia
  Corporation OUI `3c:6d:66`, since the Shield doesn't have a fixed/known IP
  ahead of time)
- ADB over network: enabled via Settings → Device Preferences → Developer
  options → Network debugging. Connect with:
  ```
  adb connect 192.168.0.81:5555
  ```
  (accept the on-device RSA key prompt the first time)
- App name: **Reelay**; applicationId: `com.reelay.tv`

## Decisions made along the way

- **Forking existing open-source clients was considered and ruled out.**
  Plex's own "Watch Together" feature is being sunset, so not worth building
  on top of. Plezy (Flutter, open source) doesn't support transcoding, which
  is a hard requirement here (subtitle burn-in for image-based subs relies on
  it).
- The cousin runs this same app on their own Android TV and account,
  pointed at the same relay — keeps the sync protocol symmetric (no need to
  reverse-engineer Plex's Companion/Remote-Control protocol to drive an
  unmodified official client).
- Relay hosting: Render.com free tier (Fly.io's free tier no longer exists as
  of 2026). Render builds `relay/` from `main`; phones only get relay changes
  (like the chat page) once it redeploys.
