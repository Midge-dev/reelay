# DESIGN.md — Reelay

Rules for writing UI in this repo. Terse on purpose: this file is meant to be
re-read on every task. Values live in `docs/tokens.json`; this file is the part
you cannot get from a token table.

Reelay is a Plex/Jellyfin client for a 10-foot display driven by a D-pad.
There is no cursor, no hover, no touch. Design system: **Nocturne**.

---

## Non-negotiables

Violating any of these is a bug, not a style preference.

1. **No hard-coded values.** Every colour, size, space, radius, duration and
   offset comes from `AppColors` / `AppSpacing` / `AppShape` / `AppElevation` /
   `AppMotion` / `AppMotionOffsets` / `AppTypography`. If the number you need
   is not there, the number is wrong — or the token is missing and should be
   added to the token file *and* `docs/tokens.json` in the same change.
2. **No glyph touches raw artwork.** Text over a poster, backdrop or video
   frame always sits on `AppScrims.edge`, `.bottom` or `.chip`, sized so the
   ground is ≥78% opaque behind the glyphs. Library artwork is unpredictable;
   this is what makes the UI safe against it.
3. **The focus signal is one token, not four.** Fill step elev2→elev3, 2px
   accent hairline, 6px accent leading spine, 1.03× scale. Never ship a subset
   and never tune them apart. On artwork cards the spine is replaced by a 3px
   frame all the way round — a spine would cover the poster.
4. **No real-time blur, ever.** No backdrop filters, no frosted panels. Also
   banned: parallax, poster shine/tilt/3D lift, glow, bloom, pulsing focus
   rings, horizontal page slides, and anything that animates while the user is
   not pressing a button.
5. **One scale factor, no breakpoints.** `scale = screenHeight / 1080`, applied
   once near the root. Sizes follow screen height; counts (grid columns, cards
   per row) follow remaining width. A second layout for "large TVs" is how this
   system dies.
6. **Text floor 17 du** (1.55% of screen height). Never scale type by pixel
   density — a 4K panel at the same physical size is not further away.
7. **Two type weights: 400 and 500.** Hierarchy is size and space. Nothing is
   bolder than 500.
8. **One accent.** `#9184D9`, as a line, a spine or a mark — never a flood, and
   never over artwork.
9. **Semantic colour is a spine plus words.** A 4px leading spine and a label,
   together. Never a coloured banner, never colour alone — a red dot on a
   washed-out LCD is not a message.

10. **A work appears once.** Items matching on provider id (Plex agent guid /
    Jellyfin ProviderIds → IMDb/TMDb) fold into one card everywhere — no badge,
    no count, no stack. No id, no folding. Source choice surfaces only at play
    time; progress is kept against the work, not the file.
11. **Empty and error take the smallest shape that fits.** Inline when the
    screen around it still makes sense; a dialog when something just asked for
    failed; full screen only when nothing is behind it. Name the cause, not the
    symptom, and every dead end carries an exit that undoes the cause.
12. **Destructive-but-reversible acts immediately and offers undo.** No confirm
    dialog for removing a watchlist or continue-watching entry — act, collapse
    the card, put an eight-second undo chip in the header. Confirm dialogs are
    reserved for acts that affect other people (ending a room).
13. **A theme may change seven values and nothing else** — ground, surface,
    raised, line, muted, accent, ink. Not spacing, radius, type, focus
    behaviour or emphasis. Status colours never re-tint. Theme is per device,
    not per profile.

## Profiles are ours, and local

A profile is **Reelay's own device-local record** — name, picture, Watch
Together name, and the accounts it signed in with. It maps to **accounts**,
which both platforms have, not to either platform's profile feature. Adding one
means signing in as that person, so restrictions are real and server-enforced.
One account per platform per profile. Not synced across devices. **Not a
security boundary** — never write copy implying the picker keeps anyone out.
The picker stays hidden until a second profile exists.

## Jellyfin: designed, not shipped

The system is server-neutral and the screens show Plex and Jellyfin as peers, but
**Jellyfin is not connectable yet.** Keep the Jellyfin card on the O1 onboarding
screen **disabled** — 45% opacity, out of the focus order, "Coming soon" — until
Jellyfin support is researched and implemented. The Link Jellyfin screen (O3) is
the target design for that work and stays unreachable until then. Do not make
the card selectable to make the layout feel finished: a dead end behind a live
card is worse than a stated one.

## Focus rules

- Exactly one focused element on screen, always.
- Focus rests on leaves, never containers.
- Every screen claims focus explicitly on entry. The rail is never left holding
  it. (Most historical focus bugs in this repo are this rule being skipped —
  see the `requestFocus` in `lobby_screen.dart` for the pattern.)
- Removing a focused item reclaims focus **inside its own row**
  (`_reclaimFocusOnRemoval` in `home_screen.dart`).
- Nothing outside the focused element animates on focus change.
- Holding the D-pad moves focus at input speed but scrolls the row **once**,
  when the key settles.
- Row scroll stops with the focused card at **80%** across the viewport, so the
  next card stays half-visible.
- A row's track is card height + `AppSpacing.rowHeadroom`, split evenly, so a
  focused card's scale and border are never clipped.
- Disabled means 45% opacity **and** removal from the focus order.

## Motion

Two curves: `AppMotion.enter` for anything arriving, `AppMotion.exit` (linear)
for anything leaving. A third curve is a bug.

`AppMotion.level` is an ordered `MotionLevel`, not a switch. When frame budget
is missed, drop one rung and stop: `noScale` → `noStagger` → `noCrossfade` →
`minimal`. **Focus itself is on no rung** — its three parts are single-pass
paints and survive to the bottom.

The test for any motion change: hold right on a row of forty posters on the
slowest supported device. Focus must keep up with your thumb and the row must
settle once. If you have to slow down for the interface, cut something — and it
is never the focus transition.

## Layout

- Rail 80. Content inset `safeX` from the rail and `safeY` top and bottom.
- Rows bleed off the right edge; the cut-off card is the affordance. Text
  blocks never bleed.
- Body copy ≤ ~44 characters per line. Hero text columns capped at 960 du.
- Card geometry is fixed: portrait 220×330, landscape and continue-watching
  372×209 with a 4px progress bar, list row ≥96 tall, person circle 130.
- Buttons are radius 8, not pills. Only avatars and seat circles are round.
- Elevation is an edge plus ambient darkness. Never stack two shadows; elev2
  has no shadow at all.

## Copy

- Sentence case. Uppercase only for the `micro` role.
- Name things plainly. Servers, codecs, bitrates and file sizes are shown, not
  hidden — the people running these servers care about them.
- Errors: name what failed, say when, say what still works, offer two actions.
  **Never print an exception string on a television.**
- Empty rows render nothing. Empty screens get one icon, one sentence of fact,
  one sentence of instruction. No illustrations.

## Watch Together

It is a standout feature and not the centre of the app. Keep it proportionate.

- The home bar is a **single fixed slot** that never multiplies. Extra rooms
  collapse into a trailing `N more rooms ›` segment. One room and five rooms
  produce the same silhouette.
- Bar priority: a room you hold a seat in → a room hosted by someone you have
  watched with → most recently started.
- Relay servers appear on the bar only when live rooms span more than one. The
  rooms panel always groups by relay, with health in the group header.
- In-player, the permanent additions are a participant strip and a sync state,
  both top-right on `scrim.chip`. The only moment Watch Together is allowed to
  be loud is when the room pauses for someone.

## Porting to another platform

`scale` is the only number that changes. tvOS lays out at 1920×1080 points on
every Apple TV, so 1 du = 1 pt and the values transfer literally. Compose TV:
`screenHeightDp / 1080`. Web: `--du: calc(100vh / 1080)`. Tablet/web at arm's
length: same tokens, scale ≈ 0.55.

Input models, one design: **D-pad** is the reference; **pointer** takes the
unfocused→focused transition on hover and keeps the spine for keyboard focus;
**touch** has no focus state, only pressed, and the spine becomes a selected
marker (minimum target 44pt).

What must survive any port: the focus signal's three parts together, the scrim
rule, two weights and one accent, the no-blur budget, the 80% scroll peek. A
platform may implement these differently. It may not drop one.

---

## Where things live

| | |
| --- | --- |
| `docs/tokens.json` | Canonical token values, with usage notes |
| `flutter/lib/theme/tokens.dart` | Colours, scrims, spacing, shape, elevation, motion, focus treatment |
| `flutter/lib/theme/typography.dart` | The eight type roles |
| `flutter/lib/kit/focusable_surface.dart` | The focus signal. Every component funnels through it — change focus here, nowhere else |
| `flutter/lib/kit/` | Button, card, chip, list row, switch, radio, icon, text |
| `design_handoff_reelay_nocturne/` | The HTML design references and the full handoff README |

Reading the design files: every frame is authored at 1:1 design units
(`width:1920px;height:1080px`) with **every value as an inline style** — no
stylesheets, no classes, no variables. Grep `data-screen-label` to find a
screen; the paragraph above each frame carries intent the pixels do not. Values
in `docs/tokens.json` win over the HTML; the HTML wins over prose.

When you add a component, add it to `kit/` and route it through
`FocusableSurface`. A one-off focusable in a screen file will drift from the
signal within two changes.
