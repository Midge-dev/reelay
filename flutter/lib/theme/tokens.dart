import 'package:flutter/widgets.dart';

/// Reelay design system — Nocturne. Every value is stated at 1080p logical
/// pixels; the app applies one scale factor for 4K rather than carrying a
/// second token set (see `theme/scale.dart`). Nothing here requires
/// real-time blur or backdrop filters. Canonical source: `docs/tokens.json`.
class AppColors {
  AppColors._();

  // ---- Surfaces, by elevation -------------------------------------------
  /// Nav rail and player chrome. Deepest step.
  static const canvas = Color(0xFF12141F);

  /// Screen background.
  static const background = Color(0xFF161826);

  /// Cards, list rows, panels.
  static const surface = Color(0xFF1D1F30);

  /// Focused fills, menus over a surface.
  static const surfaceRaised = Color(0xFF252840);

  /// Dialogs and popovers sitting over a scrim.
  static const surfaceOverlay = Color(0xFF2E3150);

  /// Idle borders and dividers.
  static const line = Color(0xFF2A2D40);

  /// Outlined controls and chip borders.
  static const lineStrong = Color(0xFF3A3D55);

  // ---- Ink ---------------------------------------------------------------
  /// Titles, focused labels, values. 14.8:1 on [background].
  static const ink = Color(0xFFE9E9ED);

  /// Body copy, synopsis, unfocused row labels. 10.5:1.
  static const ink2 = Color(0xFFC8CAD8);

  /// Metadata, captions, kickers. 5.4:1 — the floor for body-size text.
  static const ink3 = Color(0xFF9093A8);

  /// Idle rail icons and chrome only — never text. 3.1:1.
  static const ink4 = Color(0xFF6E7188);

  /// Any glyph over artwork or video. Always paired with a scrim.
  static const inkOnArt = Color(0xFFF4F4F7);

  // ---- Accent ------------------------------------------------------------
  /// Tint fills.
  static const accent900 = Color(0xFF2A2745);

  /// Pressed state, accent dividers.
  static const accent700 = Color(0xFF5F55A0);

  /// Base. Focus hairline and spine. 4.9:1 on [background] — chrome, icons
  /// and large text, not body copy.
  static const accent = Color(0xFF9184D9);

  /// Accent-coloured text at body size.
  static const accent300 = Color(0xFFB6ACEC);

  // ---- Semantic ----------------------------------------------------------
  /// Relay connected, room in sync, complete.
  static const success = Color(0xFF6FB98A);

  /// Reconnecting, drift correcting, transcoding.
  static const warning = Color(0xFFD8A14B);

  /// Server unreachable, playback failed, room closed.
  static const error = Color(0xFFD4756A);

  static const transparent = Color(0x00000000);

  /// Disabled content: 45% of whatever ink is in play. Disabled elements are
  /// also removed from the focus order, not merely dimmed — see
  /// `AppFocusTreatment` / `FocusableSurface`, which apply this as a whole-
  /// element opacity rather than a per-color alpha for anything focusable.
  static Color disabled(Color contentColor) => contentColor.withValues(alpha: 0.45);
}

/// Scrims. The rule this encodes: no glyph ever touches raw artwork. Every
/// text element over a poster, backdrop or video frame sits on one of these,
/// sized so the ground is at least 78% opaque directly behind the glyphs.
/// All three are gradient or flat fills — never a blur.
class AppScrims {
  AppScrims._();

  /// Hero and detail left column: artwork fades in from the leading edge.
  static const edge = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF161826), Color(0xED161826), Color(0x59161826)],
    stops: [0.0, 0.42, 1.0],
  );

  /// Card captions and player controls.
  static const bottom = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00161826), Color(0xF512141F)],
    stops: [0.0, 0.78],
  );

  /// Flat plate behind short labels on unpredictable artwork.
  static const chip = Color(0xC712141F);

  /// Behind a dialog. Flat, not blurred.
  static const dialog = Color(0xD1090A10);
}

/// Unchanged from the previous system — the scale was derived from real
/// usage and is still right. [safeX]/[safeY] are new: the screen edge was
/// being hand-typed as 48 in a dozen files.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Nav rail width, collapsed.
  static const rail = 80.0;

  /// Content inset from the rail (or screen edge) and from top/bottom.
  static const safeX = 48.0;
  static const safeY = 48.0;

  /// Gap between cards in a horizontal row.
  static const cardGap = 20.0;

  /// Extra cross-axis height a row reserves so a focused card's scale and
  /// border are never clipped: card height + this, split evenly.
  static const rowHeadroom = 24.0;
}

class AppShape {
  AppShape._();

  /// Chips, progress tracks, small plates.
  static const radiusSm = 6.0;

  /// Cards, buttons, panels, list rows.
  static const radiusMd = 8.0;

  /// Dialogs.
  static const radiusLg = 12.0;

  /// Standard border stroke.
  static const borderWidth = 2.0;

  /// The focus spine on the leading edge of a non-artwork surface.
  static const spineWidth = 6.0;

  /// Artwork cards take a frame instead of a spine — a spine would cover
  /// the poster.
  static const artFrameWidth = 3.0;
}

/// Elevation is an edge plus ambient darkness. Never stack two shadows.
class AppElevation {
  AppElevation._();

  /// elev2 — no shadow at all, a 1px [AppColors.line] edge only.
  static const List<BoxShadow> surface = [];

  /// elev3 — focused surfaces, menus.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x8006070C), blurRadius: 12, offset: Offset(0, 2)),
  ];

  /// elev4 — dialogs, over [AppScrims.dialog].
  static const List<BoxShadow> overlay = [
    BoxShadow(color: Color(0xB306070C), blurRadius: 40, offset: Offset(0, 8)),
  ];
}

/// How far things travel. Paired with [AppMotion] — a duration without its
/// distance is half a spec, and these were the numbers most likely to get
/// retyped per screen.
class AppMotionOffsets {
  AppMotionOffsets._();

  /// Row entrance: each card rises this far as it fades in.
  static const rowEntranceRise = 8.0;

  /// Forward page transition: incoming screen rises this far.
  static const pageRise = 12.0;

  /// Back: incoming screen falls this far instead.
  static const pageFall = 4.0;

  /// Player controls rise with their scrim.
  static const controlsRise = 16.0;

  /// Side panels (subtitle/audio menu, server switcher) translate in.
  static const panelTranslate = 24.0;

  /// Dialogs scale from this to 1.0.
  static const dialogScaleFrom = 0.98;

  /// The one interruption allowed to scale in more assertively: the
  /// "paused for the room" card.
  static const roomInterruptScaleFrom = 0.96;

  /// Scrubber thumb, unfocused to focused.
  static const scrubThumbIdle = 16.0;
  static const scrubThumbFocused = 20.0;
}

/// Degradation ladder. Not a bool: the rungs are ordered, and the right
/// behaviour is to drop one at a time and stop as soon as frame budget
/// holds. Focus itself is never on the ladder — fill, hairline and spine
/// are single-pass paints and survive to [minimal].
enum MotionLevel {
  /// Everything in [AppMotion].
  full,

  /// Drop the focus scale and the elev3 shadow.
  noScale,

  /// …and the row-entrance stagger.
  noStagger,

  /// …and artwork/backdrop crossfades — cut instead of fade.
  noCrossfade,

  /// …and page transitions. Focus transition only.
  minimal,
}

/// One easing curve for everything that enters; linear for everything that
/// leaves. Every duration the system uses lives here — if a screen needs a
/// number that is not in this class, the number is wrong.
class AppMotion {
  AppMotion._();

  static const enter = Cubic(0.2, 0, 0, 1);
  static const exit = Curves.linear;

  // ---- Focus -------------------------------------------------------------
  /// Fill step, hairline fade and the 1.03x scale.
  static const focusEnter = Duration(milliseconds: 120);

  /// The spine wiping out from the leading edge, 0 -> spineWidth. Slightly
  /// ahead of [focusEnter] so the edge lands before the scale settles.
  static const focusSpineWipe = Duration(milliseconds: 100);
  static const focusExit = Duration(milliseconds: 90);
  static const press = Duration(milliseconds: 90);

  // ---- Rows and pages ----------------------------------------------------
  /// Row eases the focused card to 80% across the viewport.
  static const rowScroll = Duration(milliseconds: 280);

  /// Per-card delay on first paint of a row.
  static const rowEntranceStagger = Duration(milliseconds: 40);

  /// Cards past this index all arrive together.
  static const rowEntranceStaggerCap = 6;

  static const pageEnter = Duration(milliseconds: 200);
  static const pageExit = Duration(milliseconds: 140);

  // ---- Imagery -----------------------------------------------------------
  /// Poster and still fade-up over the placeholder tone.
  static const artworkFade = Duration(milliseconds: 180);

  /// Detail backdrop crossfade — the slowest move in the app, behind an
  /// already-complete layout.
  static const backdropFade = Duration(milliseconds: 320);

  // ---- Chrome ------------------------------------------------------------
  static const overlayIn = Duration(milliseconds: 160);
  static const overlayOut = Duration(milliseconds: 120);

  /// Active spine sliding between rail items, and the rail's own
  /// expand-to-labels when focus enters it.
  static const railSlide = Duration(milliseconds: 180);

  /// Seek-preview frame trails the scrub position by this much; reads as
  /// weight rather than lag.
  static const seekPreviewLag = Duration(milliseconds: 60);

  static const controlsAutoHideDelay = Duration(milliseconds: 3000);
  static const toastVisible = Duration(milliseconds: 6000);
  static const toastFadeOut = Duration(milliseconds: 300);

  /// Skeleton pulse — a whole-row opacity breath, not a gradient sweep.
  static const skeletonPulse = Duration(milliseconds: 2400);

  // ---- Degradation -------------------------------------------------------
  static MotionLevel level = MotionLevel.full;

  static bool get scaleOnFocus => level == MotionLevel.full;
  static bool get staggerRows => level.index <= MotionLevel.noScale.index;
  static bool get crossfadeArtwork => level.index <= MotionLevel.noStagger.index;
  static bool get animatePages => level.index <= MotionLevel.noCrossfade.index;
}

/// The focus treatment, as one paired token. Three stacked signals: the fill
/// steps up an elevation, a 2px accent hairline appears, and a 6px accent
/// spine lands on the leading edge. The spine is the one you read from the
/// sofa. All three are single-pass paints, so the lightweight fallback is
/// simply: keep them and drop [focusScale] and the raised shadow.
class AppFocusTreatment {
  AppFocusTreatment._();

  static const idleBorderColor = AppColors.line;
  static const idleBorderWidth = AppShape.borderWidth;
  static const idleContainer = AppColors.surface;
  static const idleContent = AppColors.ink2;

  static const focusedBorderColor = AppColors.accent;
  static const focusedBorderWidth = AppShape.borderWidth;
  static const focusedSpineColor = AppColors.accent;
  static const focusedSpineWidth = AppShape.spineWidth;
  static const focusedContainer = AppColors.surfaceRaised;
  static const focusedContent = AppColors.ink;

  /// Selected but not focused: the spine goes ink, the fill stays put.
  static const selectedSpineColor = AppColors.ink;

  static const pressedContainer = AppColors.accent900;
  static const pressedBorderColor = AppColors.accent700;

  /// Barely perceptible up close, and legible in aggregate across a row.
  /// Dropped entirely in low-power mode.
  static const focusScale = 1.03;

  /// Artwork cards: a frame all the way round instead of a spine.
  static const artFrameColor = AppColors.accent;
  static const artFrameWidth = AppShape.artFrameWidth;
}
