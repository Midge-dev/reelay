# Recorded Watch Together sessions

Each folder here is one room, as the devices in it recorded it. `trace_replay_test.dart`
replays every folder through the room simulation, and the room has to settle. So a
session that went wrong becomes a test that keeps it from coming back.

`example-guest-rewind/` came from the simulation itself (a guest on a slow remote
transcode rewinds 30s). It's here to show the format and to keep the loading path tested.

## Getting a trace off a device

Every time a device is in a room, it writes `sync-traces/<start time>.jsonl` and keeps
the newest 10.

**Shield / Android TV.** Any build, no `run-as` needed:

```
adb pull /sdcard/Android/data/com.reelay.tv/files/sync-traces
```

**Mac.** `~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/sync-traces/`
for a sandboxed build, or `~/Library/Application Support/<bundle id>/sync-traces/` otherwise.

Pick the file whose start time matches the session (its first line has the trace path).

## Adding one

1. Make a folder named for what happened, e.g. `2026-11-18-rewind-loop/`.
2. Put each device's file in it, named for the device: `host.jsonl`, `shield.jsonl`.
   One device's file is enough. The other side is filled in from what that device heard.
3. `flutter test test/sync/trace_replay_test.dart`. On failure, the output shows the
   scenario read from the traces (players, clocks, what everyone pressed when), the room
   once a second, and the interleaved traces.

To dig in by hand, `scenarioFromTraces` (`test/sync/sim/trace_replay.dart`) gives you
the `Scenario`, and `runRoom` runs it.

## What's in a trace

One JSON object per line; `t` is that device's own clock in ms. See
`lib/sync/sync_trace.dart` for the full list: `session` (role), `in`/`out` (sync relay
events, with chat and presence left out), `call` (the engine told the player to
play/pause/seek), `player` (what the player reported; a `seek` with no `call seekTo`
just before it was the person's own), and `sample` (once a second: position, state,
clock offset).
