# Reelay — Cross-Platform Design Tokens

Values, not code. This spec exists because there is no single UI framework
that runs on all target platforms — Compose (`androidx.tv.material3`) is
Android/Fire TV-only, doesn't reach tvOS or Roku; Compose Multiplatform
doesn't target tvOS either; Roku's BrightScript/SceneGraph environment can't
host any external framework at all, full stop. So instead of one shared
component library, each platform gets its own **native** component set
(Compose today, SwiftUI for Apple TV, SceneGraph/BrightScript for Roku), and
this doc is the thing all of them implement against, so the app looks and
feels like one product everywhere. See `NOTES.md` for the toolchain/backend
side of the cross-platform plan; this file is UI-only.

Current values below are extracted from the live Android implementation
(`app/src/main/java/com/reelay/tv/ui/theme/`) — Android stays the
reference implementation; nothing here changes what's on screen today.

## Color

| Token | Value | Usage |
|---|---|---|
| `color.background` | `#0D0D12` | Screen background |
| `color.onBackground` | `#F2F2F5` | Text/icons on background |
| `color.surface` | `#17171D` | Cards, panels, menus |
| `color.onSurface` | `#F2F2F5` | Text/icons on surface |
| `color.surfaceVariant` | `#2A2A33` | Secondary surface (e.g. unselected chip fill) |
| `color.onSurfaceVariant` | `#C7C7D1` | Text/icons on surfaceVariant |
| `color.accent` (NeonPurple) | `#AD2BD7` | Focused-state fill, brand accent |
| `color.accentGlow` (NeonPurpleGlow) | `#E795FC` | Outer stop of the focus-glow gradient, elevation glow color |
| `color.onAccent` | `#FFFFFF` | Text/icons on filled accent surfaces |
| `color.white` | `#FFFFFF` | Content over video/photos/QR — literal white, not `onBackground`, for max contrast on unpredictable backdrops |
| `color.scrim` | `#000000` | Overlay backgrounds behind floating text/controls |
| `color.dimBorder` | `#444444` | Idle/unfocused outline (inputs, idle card borders) |
| `color.disabled` | `onSurface/onAccent @ 50% alpha` | Disabled content — alpha applied to whichever content color is in play, not a separate flat color |

Rationale carried over from Android: the base dark palette is deliberately
higher-contrast than typical Material dark defaults, because low-contrast
"tuned for phone at arm's length" dark themes read poorly from a couch on a
real TV panel. Keep that bias on every platform — don't let a platform's
default dark theme quietly override it.

## Focus & glow treatment

This is the app's visual signature and the single most important thing to
reproduce identically: every focusable element (button, card, chip) gets a
**two-tone radial-gradient border** (inner stop `accentGlow` → outer stop
`accent`) plus a **matching elevation/drop glow** in `accentGlow`, both only
on focus — idle state is `dimBorder`, no glow. Concretely, at rest:

- Border: 2pt solid `dimBorder` (or transparent, context-dependent — see
  component inventory below)
- Glow: none

On focus:

- Border: 2pt radial gradient, `accentGlow` → `accent`
- Glow: `accentGlow`, ~12pt elevation/blur

Treat gradient border + glow as one paired token
(`focusTreatment.border` / `focusTreatment.glow`), not two independent
choices — they've always shipped together on Android and should stay
paired everywhere. **Open question, not yet verified:** whether Roku's
SceneGraph focus system (`Rectangle`/`focusable` nodes) can produce a
gradient stroke and a soft elevation glow the same way, or whether the
Roku implementation needs a simplified fallback (e.g. flat accent-color
border, no glow) — check this during Roku scoping rather than assuming
parity is free there.

## Horizontal browsing rows (edge fade, safe margin, scroll peek)

Added during the Flutter port's on-device Shield pass (2026-09-19/20),
after real-remote testing surfaced it — not present as an explicit spec
before, so this section is new, not extracted from the Android
implementation like the rest of this file. Applies to any single-row
horizontally-scrolling strip of focusable cards (movie/show posters,
cast/crew avatars, room cards) — not to vertically-scrolling grids,
which don't have "more content this way" to hint at, and not to fixed
participant/roster rows.

- **Edge fade:** the row's leading and trailing edges fade to transparent
  over `space.xxxl` (48) — a `dstIn`-blended linear gradient across the
  row's own width, always on regardless of scroll position (not
  conditional on whether there's genuinely more content in that
  direction). This is the "more this way" affordance most TV browsing
  UIs use.
- **Safe margin:** the row's leading/trailing content padding is
  `space.xxxl` (48), not the general `space.xxl` (32) — a card's
  focus-scale/glow needs headroom against the actual screen edge, not
  just against its own row bounds, and a card sitting at the very start
  or end of a row has no neighbor on that side to borrow visual space
  from the way a mid-row card does.
- **Vertical headroom:** a row's cross-axis size (its fixed height, on
  a platform whose scroll container needs one) must be taller than the
  unfocused card's own content height — roughly the card height plus
  24, split above and below as vertical padding — so a focused card's
  scale can grow without being clipped, *and* so the edge-fade effect's
  own bounds fully contain that scaled card. A fade that only masks
  within a tightly-fit row height, while the scale is allowed to
  overflow past it, leaves the overflowing sliver unfaded — visible as
  a seam at the top of a focused card sitting near the fade zone.
- **Scroll peek:** when a card gains focus and the row must scroll to
  reveal it, stop with the focused card fully visible but offset from
  the trailing edge — roughly 80% across the viewport, not flush at
  100% — so the next card is deliberately left partially visible
  (faded) rather than fully hidden. Reads as "here's what's next," not
  just "here's what's focused."

## Spacing scale

Derived from actual usage frequency across the Android codebase (values
below appear 8+ times each; treat as the canonical scale rather than
picking arbitrary new numbers per screen):

| Token | Value |
|---|---|
| `space.xs` | 4 |
| `space.sm` | 8 |
| `space.md` | 12 |
| `space.lg` | 16 |
| `space.xl` | 24 |
| `space.xxl` | 32 |
| `space.xxxl` | 48 |

Units are intentionally unitless here — each platform maps this to its own
native unit (`dp` on Compose, points on SwiftUI, pixels/`translation` on
SceneGraph). Don't assume 1 token unit == 1dp == 1pt; each platform should
tune the scale's absolute size for legibility at its own typical TV
viewing distance/resolution, keeping the *ratios* between steps fixed.

## Shape

| Token | Value | Usage |
|---|---|---|
| `radius.sm` | 8pt | Cards |
| `radius.pill` | fully rounded (50%) | Buttons |
| `border.width` | 2pt | Standard focus/idle border stroke width everywhere |

## Typography

Roles, not pixel sizes — Android's exact `dp` type-scale values don't mean
anything on SwiftUI's point system or Roku's font renderer, so the shared
contract is the **role hierarchy and where each role is used**, not a
number to copy. Each platform should pick its own TV-legible sizes per
role (SwiftUI's tvOS default type ramp and typical BrightScript TV font
sizes are both reasonable starting points), preserving this hierarchy:

| Role | Used for |
|---|---|
| `type.displaySmall` | Largest hero/title text (e.g. movie title on detail screen) |
| `type.displayMedium` | Secondary hero text |
| `type.headlineMedium` / `type.headlineSmall` | Section headers |
| `type.titleLarge` / `type.titleMedium` | Card/list-item titles, dialog headers |
| `type.bodyLarge` / `type.bodyMedium` | Body copy, descriptions, chat text |

## Motion

| Token | Value | Usage |
|---|---|---|
| `motion.controlsAutoHideDelay` | 3000ms | Player transport controls auto-hide after inactivity |
| `motion.toastVisible` | 6000ms | Chat message stays visible before fading |
| `motion.toastFadeOut` | 300ms | Chat message fade-out duration |

## Component inventory (native-equivalent checklist)

What today's Android/`androidx.tv.material3` screens are actually built
from — this is the checklist for "what does the tvOS/Roku UI need to have
a native equivalent of" when that work starts. From the full audit in
`NOTES.md` (2026-08-17):

**Library components in use** (need a native counterpart with matching
focus/glow treatment): Button/OutlinedButton, Card, FilterChip, Icon,
ListItem, NavigationDrawer, RadioButton, Surface, Switch, Text, a
Material-loading-indicator equivalent.

**Hand-rolled, no library equivalent existed on Android either** (these
need a bespoke native build on every platform, not just a port — nothing
to "migrate from"):
- Custom scrollbar (`NeonScrollbar.kt`)
- Text input field (`ClickToTypeTextField` — on-screen-keyboard-driven,
  since TV has no physical keyboard)
- Toast-style fading message list (`ChatOverlay.kt`)
- In-player subtitle picker panel and a remove-confirmation panel
  (dialog-shaped, but no dialog/bottom-sheet primitive was available)
- Long-press-to-remove poster card (needed long-click, which the base
  `Card` component doesn't expose)

Since none of these ever came from a component library even on Android,
there's no "library API to match" for tvOS/Roku either — build each
against the tokens above (color, focus treatment, spacing, shape) directly.

## Maintenance

Android (`ui/theme/AppColors.kt`, `ui/theme/NeonPurpleButtonStyle.kt`)
stays the source of truth for values while it's the only shipped platform.
Once a second platform is real, promote this file to the actual source of
truth and have Android's token file cite it instead of the reverse, so
values don't drift out of sync in either direction.
