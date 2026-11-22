# Reelay — Architecture notes

The reasoning behind the parts of Reelay that aren't obvious from the code:
the Watch Together relay and sync model, Plex API quirks, and a few
defaults with history. For the UI rules read [`DESIGN.md`](DESIGN.md); for
how to run and test, [`.claude/CLAUDE.md`](../.claude/CLAUDE.md).

## 1. Project shape

- `flutter/lib/` — the app.
  - `screens/app_root.dart` switches on one sealed `AppState`
    (`state/app_state.dart`), driven by `state/app_root_controller.dart`.
    There is no Navigator route stack: a screen's `returnState` is its Back
    target, and `focus/screen_memory.dart` gives each state object its
    focused item, scroll offsets and screen-local state, so Back returns
    to a screen as it was left.
  - `kit/` — Nocturne components; every focusable routes through
    `kit/focusable_surface.dart`.
  - `focus/` — `BackHandler` (one handler answers each Back press),
    screen memory, D-pad long-press, row-end stop.
  - `data/media/` — the backend-neutral seam: `MediaServer`, the content
    models (`MediaItem`, `MediaDetail`, …) and `MediaServerClient`, the one
    interface every screen, state object and the player talk to. Build a
    client with `MediaServerClient.forServer`, which picks the backend.
  - `data/plex/` — the Plex backend: `PlexClient` implements
    `MediaServerClient` and maps Plex's wire models (`plex_models.dart`)
    into the neutral ones (`plex_mappers.dart`). Nothing outside `data/`
    touches a Plex content type; the Plex *account* layer (sign-in,
    resources, watchlist) is still used directly by `AppRootController`.
  - `state/duplicate_fold.dart` folds the same title across servers into
    one work, on the provider ids (`imdb://`, `tmdb://`, `tvdb://`) every
    backend reports the same way.
  - `sync/` + `playback/` — the Watch Together client, sync model and player
    glue.
- `relay/` — the Watch Together WebSocket relay (Node.js, `server.js`) and
  the phone chat page (`chat.html`).

## 2. Watch Together / relay sync

### 2.1 Protocol and room intent

Every device connection states its room intent up front (create or join)
rather than a single-tenant "hello" — one relay hosts many independent
rooms, each identified by a `roomId` learned from the `/rooms` directory.
`RelayEvent` (`sync/relay_protocol.dart`) is one flat type carrying every
event kind (playback state, control requests, peer status, clock ping/pong,
presence, chat): every field is optional, and the relay never inspects
payloads, it just rebroadcasts them to every other peer. Whoever receives a
kind irrelevant to their role ignores it.

"Room closed" is kept distinct from "room not found": both mean the room is
gone, but closed comes from an explicit `closed` frame the relay sends the
instant a host deliberately ends a session — a clean signal rather than the
transient-looking dropped socket that not-found covers.

### 2.2 Room and seat lifecycle (relay)

A room lives as long as *anyone* is seated — the host dropping doesn't end
it, since a guest mid-movie shouldn't be cut off by the host's connection.
It's deleted only once every seat has been empty for
`EMPTY_ROOM_TIMEOUT_MS` (10 minutes) straight, tracked by an `emptySince`
timestamp cleared the instant anyone is seated again. Seat 0 is always the
host. Guests keep their seat across reconnects by presenting the
`reconnectToken` minted the first time; a token that doesn't match (a
partial storage clear, a regenerated peer id) falls through to a fresh seat
rather than failing — otherwise a device that only lost its token was told
the room was full with seats open.

The directory (`GET /rooms`) only lists a room while its host is
connected. So a host leaving the lobby or player doesn't disconnect: the
app keeps the connection for up to three minutes while they browse
(`AppRootController.leaveRoom`), which keeps the room listed and joinable.
It ends — closed for everyone — when that runs out, on End session, or
when the host plays or hosts something else; going back into the same
title's room takes it up again. This is client-side on purpose, so it
works against any relay, including one a friend runs.

Deliberately ending a room (`POST /rooms/:roomId/close`) is a different path
from a disconnect, which still gets the reconnect grace — losing power or
wifi never silently ends a room. On a deliberate close *every* occupied seat
gets a `{"type":"closed"}` frame before its socket closes, so a waiting
guest sees an ending, not a transient failure. The ghost-connection reaper
uses `terminate()`, not `close()`: a non-responding socket may not complete
a graceful close, and `terminate()` frees the seat immediately instead of
waiting on a TCP timeout that may never fire through a hosting proxy.

### 2.3 Resource limits and security (relay)

- **One malformed message used to be able to crash the process.**
  `JSON.parse("null")` succeeds; reading `msg.type` on it then threw inside
  a WebSocket callback, taking down every room. Fixed with a type guard
  before dispatch.
- **The HTTP routes check `RELAY_TOKEN`** (`GET /rooms`, the close
  endpoint), not only the WebSocket upgrade.
- **Caps** on rooms (`MAX_ROOMS`), seats (`MAX_DEVICE_SEATS`), phone chat
  peers (`MAX_CHAT_PEERS`) and client-supplied string lengths. This is a
  self-hosted relay for one friend group; the caps are a backstop against
  one bad client, not a sign real use approaches them. The close endpoint's
  body is capped before parsing.

The upgrade handler uses `noServer: true` with a manual `upgrade` listener,
so a bad token is rejected *before* the handshake completes — an immediate
HTTP error instead of a connection accepted then closed, which measured as
a ~20-second code-1006 disconnect through the hosting proxy.

### 2.4 Reconnect and backoff (client)

`RelayClient` (`sync/relay_client.dart`) owns a connection's lifecycle end
to end, and every ending falls through to the same place that schedules a
reconnect. `retryNow()` (the lobby's Retry) starts a new attempt
immediately, but the old attempt's cleanup can still run *after* the new one
has connected — nulling out a connection that just succeeded and queuing a
spurious extra reconnect. A monotonic `_connectionGeneration` guards this:
only the attempt that is still the current generation may act. This is the
load-bearing invariant of the reconnect path.

"Room full" and "room not found" are terminal rejections, not transient
failures; the client shows the specific rejection instead of a generic
"reconnecting", while still retrying on a timer (the host could free a
seat).

### 2.5 Playback sync

The host owns the authoritative playback state; guests reconcile their
player toward it rather than trusting their own play/pause/seek history.
This replaced a design where a guest's own buffering could be broadcast as
a false pause — the original "spotty sync" — which is why peer status
reports buffering separately from ready/play intent.

`HostPlaybackCoordinator` and `GuestPlaybackReconciler` follow a Dart
reference implementation (Plezy): the same phase machine and
peer-status-driven stall gating, but without per-media epochs (each
`PlayerScreen` is already scoped to one title) or RTT-adaptive start delay —
a fixed start delay instead. Drift is corrected two ways: a hard seek past
the deadband, and inside it, playing a little fast or slow
(`SyncedPlayer.setPlaybackRate`; ExoPlayer holds the pitch).

Tuning with history behind it:

- `_stallGraceMs` (2500 ms) was widened twice (500 → 1500 → 2500) after
  real use kept hitting stall/resume cycles that pointed at one side not
  sustaining the transcode bitrate — every buffer pausing the whole room is
  far more visible than one client buffering quietly. A chronically
  insufficient bitrate needs fixing in Settings, not a bigger number here.
- The guest deadband (`_deadbandMs`, 1500 ms) started at 350 ms. With a
  hard seek the only correction, normal WAN clock-sync jitter across a
  relayed, cross-household connection routinely exceeds a few hundred
  milliseconds — at 350 ms nearly every cooldown cycle caused a disruptive
  re-seek and rebuffer. But at 1500 ms nothing corrected a gap under it at
  all, and a guest could watch a second behind for a whole film (a 1 s
  hiccup is under the host's stall grace, so the room plays on). Since
  2026-11-19 the guest closes such a gap by rate: 5% from 150 ms off, 10%
  from 500 ms, back to real time inside 50 ms — a second in about ten
  seconds, with no rebuffer. Seeks stay for anything past the deadband.
- The host holds its own player at the start spot through the start delay
  (`_startDelayMs`, 750 ms). A play press starts ExoPlayer at once; left
  running, the host got that far ahead, the start seeked it back, the seek
  rebuffered, and a rebuffer just after a seek stalls the host — so the room
  began by waiting on its own host. Found 2026-11-19 by a whole-app journey
  once the guest started nudging; it's the same play → seek back → buffer
  shape as that night's on-device loop.
- An explicit seek pins the room: from someone's seek until the room plays
  again, it resumes where they asked, and stalled peers' positions no
  longer move the host (`_explicitSeekAtMs`). A peer still on its way to
  the previous spot reported it and pulled the host back, losing the seek
  (fuzz seed 1975). A wait that starts well after the seek isn't pinned.
- `_rendezvousToleranceMs` and the guest's alignment while the room waits
  are the deadband (1500 ms), not 500: since rate nudging, a smaller gap
  is closed by speed after the room resumes. At 500 a slow transcode that
  landed and played half a second on chased the host through every wait
  (fuzz seed 1968). Paused rooms still align to 500 ms — a still frame.
- A guest that has to seek just before the room starts aims where the room
  will be when its seek lands (the start spot plus its measured seek lead,
  less the time left before the start), as a seek while playing does. Aimed
  at the start spot, a slow seek landed behind a room already playing, the
  room rewound to wait for it, and the other guests then had to seek back —
  two slow guests took turns (fuzz seed 6530). With it, 10000 of 10000
  random rooms settle.
- `_intendedPlaying` defaults to `true`: the player starts playing on
  creation, before the coordinator is listening, so a `false` default meant
  every session needed a manual Play press to get going.

Seeks with slow players (2026-11): a seek on a remote Plex transcode can
take seconds to play again, and the engine used to turn that into a loop —
the host played on through its stall grace, paused the room *ahead* of the
slow guest, resumed there, so the guest seeked, stalled, and fell behind
again, forever. The "stall/resume cycles" behind the grace widenings above
were probably this, which a wider grace makes worse, not better. The rules
now:

- **When the room waits for you, it comes to you.** Waiting for a stalled
  peer, the host seeks itself to that peer's reported position (within 2
  minutes) and resumes there; a guest the host is waiting on doesn't seek.
- **A guest reports where it's going, not where it was.** While a seek is
  buffering, its status carries the seek target (the player still reports
  the old position), and it doesn't restart a seek still landing unless the
  host's target is 10 s+ away. Catch-up seeks while playing aim ahead by
  how long the last one took (capped at 2 s).
- **The host treats its own post-seek buffering as a stall at once**, holds
  (paused) through a waiting room after its own stall, and starts no one
  until its own player is ready.
- **The relay announces `peerLeft`** when a device's socket closes, so a
  host isn't left waiting the 15 s safety timeout for a guest that's gone.

Binging in a room (2026-11): the host's Next episode (its button, Up Next,
or a guest's `controlRequest` of kind `next`) sends `episodeSwitch` before
its own player moves on: the room's new title, the host's item and server,
the episode's provider ids, the show's title and ids, and its season and
episode numbers. A guest stops its old stream's sync at once — left
running, it would tell the host's new session it's ready while still on the
old episode — then plays the host's own item if it shares the server, else
that season/episode of the show it's already watching, else the show found
by title and matched on its ids (`resolveEpisodeSwitch`). The host's new
session is handed the room's guests (`SyncViewModel.initialPeers`) so it
waits for them to load rather than starting alone. The relay renames the
room from the host's switch, so the directory and late joiners follow.

During playback every client also sends `presence` (name, avatar) every
3 s (`sync/room_roster.dart`), which is what turns the sync layer's peer ids
into "Holding for Marcus".

### 2.6 Clock sync

Two TVs on two networks have no reason to agree on wall-clock time; an old
engine compared raw timestamps and assumed they did. `ClockSync`
(`sync/clock_sync.dart`) runs NTP-style offset estimation against the host,
keeping a rolling window of samples and reporting the offset of the
*lowest-RTT* sample — one clean exchange beats an average polluted by
jittery ones. `_maxAcceptedRttMs` is 5000 ms, far above a LAN default,
because two households on residential internet through a relay hop
regularly see round trips over a second; rejecting those left the offset
unresolved forever, silently assuming zero clock difference and turning any
real difference into permanent "drift" and a hard seek every cycle.

### 2.7 Testing sync, and traces from real rooms

`test/sync/sim/` runs whole rooms in fake time: the real `SyncViewModel`
(so host and guest engines, wire format and clock sync) per device, a
`SimPlayer` that behaves like `video_player` (intent-style `isPlaying`,
polled position, seconds-long seeks on a transcode), and a relay with
per-link delay and jitter. `room_scenarios_test.dart` covers things that
happen in real rooms; `room_fuzz_test.dart` runs random rooms from seeds
(`SYNC_FUZZ_SEED=n` replays one, `SYNC_FUZZ_RUNS=2000` for a deeper run).
A room passes when every guest is within 2 s of the host, all doing the same
thing, soon after the last action, without excessive corrective seeks — and
then ends on the host's frame: within 250 ms, less what clock sync can't
see (half the difference between a link's two directions; NTP has the same
blind spot). On that bar the hard-seek-only guest failed 444 of 1000 random
rooms; with rate nudging, none (1 of 3000, seed 1975, thrashes with seeks
the same way on both).

The simulation can't tell you what real players and servers do — how long
a transcode really takes to seek, whether ExoPlayer reports buffering on
every seek. For that, every device in a room writes a trace
(`sync/sync_trace.dart`, `sync-traces/*.jsonl`), and
`test/sync/traces/` turns a real session back into a scenario; see its
README.

### 2.8 Phone chat

The relay serves `relay/chat.html` at `/chat` (read from disk at start-up,
`Cache-Control: no-cache`). The TV's QR link carries `&theme=<ThemeId.name>`
so the page matches the TV that showed it; `chatHistory` carries the room
title for its header. The page's palettes are copies of `tokens.dart`, kept
in step by `test/theme/chat_page_palette_test.dart`.

## 3. Plex API notes

Response-shape quirks confirmed against a real server:

- `includeReviews=1` is required for the `Review[]` array; without it the
  key is absent.
- `/hubs/home` (plex.tv's cloud Discover path) 404s against a local server;
  `/hubs/promoted` is the local path behind the official app's home rows.
  Its suggestions hub only exists when the server has something to offer,
  so empty is a valid state; its identifier isn't stable across server
  versions and is matched by substring.
- A show's own metadata fetched with `includeOnDeck=1` embeds the next-up
  episode; there is no `/onDeck` sub-resource (404).
- An empty `Metadata` array for a detail fetch is a real response (a
  `ratingKey` deleted or moved since it was linked), not a parse failure.
- Cast/crew headshots come back as absolute URLs (`metadata-static.plex.tv`),
  unlike most thumb/art fields, which are server-relative — prefixing them
  with the server's base URL makes a silently broken image.
- `/library/recentlyAdded` surfaces TV at *season* granularity;
  `parentTitle`/`parentRatingKey` are the show, used to open the show's page.
- **People:** `/library/people/<id>/media` lists everything a person is
  credited on across a server's sections. Its items' `Role` lists only the
  first three names, without characters — the character and whether they
  directed or wrote come from each title's own detail. A person's `id` is
  per-server; search's actor hub carries Plex's global `tagKey`, which is
  how the same person is found on another server. The `director=` filter
  was not reliable for splitting acting from directing.
- Plex returns nothing for one-character searches.

## 4. Settings

`AppSettings.relays` starts empty — a baked-in default relay doesn't
generalize once the app is shared beyond one household. `RelayEntry.isDefault`
picks the relay new rooms are hosted on; `SettingsStore` normalizes to
exactly one default on save. `maxHostSeats` is a client-side cap sent at
room creation; the relay's `MAX_DEVICE_SEATS` is the real ceiling, and
lowering it never evicts anyone from a live room.

The legacy single-URL → relay-list migration in `SettingsStore` is guarded
by a mutex: two readers at cold start could otherwise both see an empty
relay list plus a legacy URL and each write their own migrated entry,
leaving duplicate rows.

## 5. Networking defaults

`plexHttpClient()` has a 15-second default timeout: an unresponsive (not
refusing) Plex server is a real home-server failure mode, and without a
timeout every call through the client hung forever with no retry state.
Callers can override it — `PlexResourcesApi`'s reachability probes use 4 s.
`RelayDirectoryApi` uses 5 s for ambient checks and a *tolerant* 75 s where
the lobby waits: a free-tier relay host that has been idle needs real time
to wake, and that is normal, not an error.
