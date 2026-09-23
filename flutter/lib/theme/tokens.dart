import 'package:flutter/widgets.dart';

/// Screen 22 — a theme sets exactly these seven values (ground, surface,
/// raised, line, muted, accent, ink) and nothing else: spacing, radius,
/// type and focus behaviour are the system, not the skin. Device-level, not
/// per-profile (DESIGN.md), so this lives in AppSettings/SettingsStore
/// alongside `relays`/`maxHostSeats`, not per-Profile.
enum ThemeId {
  nocturne('Nocturne', 'Muted periwinkle on blue-grey. The default.'),
  projection('Projection', 'No colour at all. Light is the accent.'),
  ember('Ember', 'Cool ground, one warm brass. Focus is warmth.'),
  harbour('Harbour', 'Steel blue, barely there. The coolest of the set.'),
  sage('Sage', 'Grey-green on near-black. Quiet and slightly organic.'),
  clay('Clay', 'Warm ground, dusty terracotta. The only warm-on-warm.'),
  quartz('Quartz', 'Dusty rose on a faint violet ground.'),
  horror('The Horror', 'Deep blood red on a red-black ground. Lights off.');

  final String label;
  final String blurb;

  const ThemeId(this.label, this.blurb);
}

/// The sixteen colors a theme actually touches once every screen's own
/// spacing/motion/shape stays fixed. Six (background, surface, surfaceRaised,
/// line, ink3, accent) are the mockup's own swatches, verbatim; the other ten
/// don't appear in the handoff at all, so each is carried over from
/// Nocturne's own hue/lightness offset (and, for the three accent tints,
/// saturation *ratio* rather than a flat offset — Harbour/Sage/Quartz's base
/// accents are already fairly desaturated, and a flat offset crushed
/// accent700/900 to plain grey) between a base role and its derived token.
class NocturnePalette {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color line;
  final Color ink3;
  final Color accent;
  final Color canvas;
  final Color surfaceOverlay;
  final Color lineStrong;
  final Color ink;
  final Color ink2;
  final Color ink4;
  final Color inkOnArt;
  final Color accent900;
  final Color accent700;
  final Color accent300;

  const NocturnePalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.ink3,
    required this.accent,
    required this.canvas,
    required this.surfaceOverlay,
    required this.lineStrong,
    required this.ink,
    required this.ink2,
    required this.ink4,
    required this.inkOnArt,
    required this.accent900,
    required this.accent700,
    required this.accent300,
  });
}

const _nocturnePalettes = <ThemeId, NocturnePalette>{
  ThemeId.nocturne: NocturnePalette(
    background: Color(0xFF161826),
    surface: Color(0xFF1D1F30),
    surfaceRaised: Color(0xFF252840),
    line: Color(0xFF2A2D40),
    ink3: Color(0xFF9093A8),
    accent: Color(0xFF9184D9),
    canvas: Color(0xFF12141F),
    surfaceOverlay: Color(0xFF2E3150),
    lineStrong: Color(0xFF3A3D55),
    ink: Color(0xFFE9E9ED),
    ink2: Color(0xFFC8CAD8),
    ink4: Color(0xFF6E7188),
    inkOnArt: Color(0xFFF4F4F7),
    accent900: Color(0xFF2A2745),
    accent700: Color(0xFF5F55A0),
    accent300: Color(0xFFB6ACEC),
  ),
  ThemeId.projection: NocturnePalette(
    background: Color(0xFF0E0F14),
    surface: Color(0xFF171922),
    surfaceRaised: Color(0xFF1E202B),
    line: Color(0xFF262936),
    ink3: Color(0xFF878B9C),
    accent: Color(0xFFEDEEF2),
    canvas: Color(0xFF090A0E),
    surfaceOverlay: Color(0xFF282A3A),
    lineStrong: Color(0xFF363A4B),
    ink: Color(0xFFDEDFE3),
    ink2: Color(0xFFBDC2CE),
    ink4: Color(0xFF676B7A),
    inkOnArt: Color(0xFFE8E9EE),
    accent900: Color(0xFF6D7281),
    accent700: Color(0xFFB5B8C2),
    accent300: Color(0xFFFFFFFF),
  ),
  ThemeId.ember: NocturnePalette(
    background: Color(0xFF0F1014),
    surface: Color(0xFF191A20),
    surfaceRaised: Color(0xFF22242B),
    line: Color(0xFF31333B),
    ink3: Color(0xFF8B8880),
    accent: Color(0xFFC89B5A),
    canvas: Color(0xFF0A0B0E),
    surfaceOverlay: Color(0xFF2D2F39),
    lineStrong: Color(0xFF43454E),
    ink: Color(0xFFD6D5D3),
    ink2: Color(0xFFC1BAB2),
    ink4: Color(0xFF676662),
    inkOnArt: Color(0xFFE2E0DC),
    accent900: Color(0xFF1F1912),
    accent700: Color(0xFF786142),
    accent300: Color(0xFFDEB87F),
  ),
  ThemeId.harbour: NocturnePalette(
    background: Color(0xFF131619),
    surface: Color(0xFF1A1E22),
    surfaceRaised: Color(0xFF222830),
    line: Color(0xFF2A313A),
    ink3: Color(0xFF8A939E),
    accent: Color(0xFF7C93A8),
    canvas: Color(0xFF0E1113),
    surfaceOverlay: Color(0xFF2C343F),
    lineStrong: Color(0xFF3B434E),
    ink: Color(0xFFE1E2E5),
    ink2: Color(0xFFC0C6D0),
    ink4: Color(0xFF6A727C),
    inkOnArt: Color(0xFFEBECF0),
    accent900: Color(0xFF171A1C),
    accent700: Color(0xFF535F69),
    accent300: Color(0xFF9CB0C3),
  ),
  ThemeId.sage: NocturnePalette(
    background: Color(0xFF14181A),
    surface: Color(0xFF1A2022),
    surfaceRaised: Color(0xFF222A2C),
    line: Color(0xFF2A3234),
    ink3: Color(0xFF8B9A96),
    accent: Color(0xFF7FA08C),
    canvas: Color(0xFF0F1214),
    surfaceOverlay: Color(0xFF2D373A),
    lineStrong: Color(0xFF3C4547),
    ink: Color(0xFFE0E3E3),
    ink2: Color(0xFFC0CDCC),
    ink4: Color(0xFF6B7874),
    inkOnArt: Color(0xFFEAEEEE),
    accent900: Color(0xFF151916),
    accent700: Color(0xFF54635A),
    accent300: Color(0xFF9FBBAA),
  ),
  ThemeId.clay: NocturnePalette(
    background: Color(0xFF171412),
    surface: Color(0xFF1E1A18),
    surfaceRaised: Color(0xFF272220),
    line: Color(0xFF322C29),
    ink3: Color(0xFF9A9088),
    accent: Color(0xFFB0826A),
    canvas: Color(0xFF110F0D),
    surfaceOverlay: Color(0xFF352E2B),
    lineStrong: Color(0xFF453F3B),
    ink: Color(0xFFE2E0DE),
    ink2: Color(0xFFCDC3BD),
    ink4: Color(0xFF776F69),
    inkOnArt: Color(0xFFEDEAE8),
    accent900: Color(0xFF181311),
    accent700: Color(0xFF695349),
    accent300: Color(0xFFC9A18C),
  ),
  ThemeId.quartz: NocturnePalette(
    background: Color(0xFF171419),
    surface: Color(0xFF1E1A20),
    surfaceRaised: Color(0xFF272029),
    line: Color(0xFF322B33),
    ink3: Color(0xFF968E99),
    accent: Color(0xFFAE8B9B),
    canvas: Color(0xFF110F13),
    surfaceOverlay: Color(0xFF352B37),
    lineStrong: Color(0xFF453D46),
    ink: Color(0xFFE3E2E3),
    ink2: Color(0xFFCBC3CC),
    ink4: Color(0xFF746E77),
    inkOnArt: Color(0xFFEEECEE),
    accent900: Color(0xFF272124),
    accent700: Color(0xFF735E68),
    accent300: Color(0xFFC9ABB9),
  ),
  // design_handoff_reelay_horror. The one accent outside the mid-ramp (red
  // reads pink on a TV at the others' chroma); its text colour, accent300,
  // is a pale rose so a kicker never reads as the error colour.
  ThemeId.horror: NocturnePalette(
    background: Color(0xFF110B0C),
    surface: Color(0xFF1A1112),
    surfaceRaised: Color(0xFF24171A),
    line: Color(0xFF301F22),
    ink3: Color(0xFF9A8889),
    accent: Color(0xFFA8363D),
    canvas: Color(0xFF0A0607),
    surfaceOverlay: Color(0xFF2E1C1F),
    lineStrong: Color(0xFF432C30),
    ink: Color(0xFFE6DDD5),
    ink2: Color(0xFFCDBFB6),
    ink4: Color(0xFF6E5C5E),
    inkOnArt: Color(0xFFEFE8E1),
    accent900: Color(0xFF2A1013),
    accent700: Color(0xFF6E2328),
    accent300: Color(0xFFE0A4A4),
  ),
};

/// The swatches a theme picker needs to preview every option without
/// applying any of them — [AppColors.applyTheme] is the only thing allowed
/// to touch the live static fields.
NocturnePalette nocturnePalette(ThemeId id) => _nocturnePalettes[id]!;

/// Reelay design system — Nocturne. Every value is stated at 1080p logical
/// pixels; the app applies one scale factor for 4K rather than carrying a
/// second token set (see `theme/scale.dart`). Nothing here requires
/// real-time blur or backdrop filters. Canonical source: `docs/tokens.json`.
class AppColors {
  AppColors._();

  static ThemeId currentTheme = ThemeId.nocturne;

  /// Screen 22 — the only place these sixteen fields are ever reassigned.
  /// Everything in the app reads them as plain static fields, so nothing
  /// else needs to change when a new theme applies; the caller is
  /// responsible for triggering a rebuild afterward (see
  /// `settingsStreamProvider` in `state/data_providers.dart`, which reapplies
  /// the persisted theme on every app-root build).
  /// The splash mark's lower bar (splash spec §3): ink, except Projection,
  /// whose accent and ink are both near-white — there it takes ink3 so the
  /// two bars stay distinct.
  static Color get splashInkBar =>
      currentTheme == ThemeId.projection ? ink3 : ink;

  static void applyTheme(ThemeId id) {
    final p = _nocturnePalettes[id]!;
    currentTheme = id;
    canvas = p.canvas;
    background = p.background;
    surface = p.surface;
    surfaceRaised = p.surfaceRaised;
    surfaceOverlay = p.surfaceOverlay;
    line = p.line;
    lineStrong = p.lineStrong;
    ink = p.ink;
    ink2 = p.ink2;
    ink3 = p.ink3;
    ink4 = p.ink4;
    inkOnArt = p.inkOnArt;
    accent900 = p.accent900;
    accent700 = p.accent700;
    accent = p.accent;
    accent300 = p.accent300;
  }

  // ---- Surfaces, by elevation -------------------------------------------
  /// Nav rail and player chrome. Deepest step.
  static Color canvas = Color(0xFF12141F);

  /// Screen background.
  static Color background = Color(0xFF161826);

  /// Cards, list rows, panels.
  static Color surface = Color(0xFF1D1F30);

  /// Focused fills, menus over a surface.
  static Color surfaceRaised = Color(0xFF252840);

  /// Dialogs and popovers sitting over a scrim.
  static Color surfaceOverlay = Color(0xFF2E3150);

  /// Idle borders and dividers.
  static Color line = Color(0xFF2A2D40);

  /// Outlined controls and chip borders.
  static Color lineStrong = Color(0xFF3A3D55);

  // ---- Ink ---------------------------------------------------------------
  /// Titles, focused labels, values. 14.8:1 on [background].
  static Color ink = Color(0xFFE9E9ED);

  /// Body copy, synopsis, unfocused row labels. 10.5:1.
  static Color ink2 = Color(0xFFC8CAD8);

  /// Metadata, captions, kickers. 5.4:1 — the floor for body-size text.
  static Color ink3 = Color(0xFF9093A8);

  /// Idle rail icons and chrome only — never text. 3.1:1.
  static Color ink4 = Color(0xFF6E7188);

  /// Any glyph over artwork or video. Always paired with a scrim.
  static Color inkOnArt = Color(0xFFF4F4F7);

  // ---- Accent ------------------------------------------------------------
  /// Tint fills.
  static Color accent900 = Color(0xFF2A2745);

  /// Pressed state, accent dividers.
  static Color accent700 = Color(0xFF5F55A0);

  /// Base. Focus hairline and spine. 4.9:1 on [background] — chrome, icons
  /// and large text, not body copy.
  static Color accent = Color(0xFF9184D9);

  /// Accent-coloured text at body size.
  static Color accent300 = Color(0xFFB6ACEC);

  // ---- Semantic ----------------------------------------------------------
  /// Relay connected, room in sync, complete.
  static const success = Color(0xFF6FB98A);

  /// Reconnecting, drift correcting, transcoding.
  static const warning = Color(0xFFD8A14B);

  /// Server unreachable, playback failed, room closed.
  static const error = Color(0xFFD4756A);

  static const transparent = Color(0x00000000);

  /// Behind a playing video: letterbox and pillarbox bars are the film's
  /// own black, never a tinted ground. Not a theme role — no theme may
  /// recolour the picture's frame.
  static const videoMatte = Color(0xFF000000);

  /// Disabled content: 45% of whatever ink is in play. Disabled elements are
  /// also removed from the focus order, not merely dimmed — see
  /// `AppFocusTreatment` / `FocusableSurface`, which apply this as a whole-
  /// element opacity rather than a per-color alpha for anything focusable.
  static Color disabled(Color contentColor) =>
      contentColor.withValues(alpha: 0.45);
}

/// Scrims. The rule this encodes: no glyph ever touches raw artwork. Every
/// text element over a poster, backdrop or video frame sits on one of these,
/// sized so the ground is at least 78% opaque directly behind the glyphs.
/// All three are gradient or flat fills — never a blur.
/// Gentle gradients. A plain two- or three-stop gradient changes slope
/// sharply where it meets a stop — most visibly where a fade meets solid
/// colour or clear — and on a TV's dark grounds the eye picks that out as
/// a line. [smooth] keeps the design's colours and positions but joins them
/// with a curve that is flat at both ends and monotone between (no
/// overshoot), sampled finely enough that it reads as one continuous fade.
class AppGradients {
  AppGradients._();

  static const _perSegment = 16;

  /// [colors] at [stops] (evenly spaced when omitted), resampled onto the
  /// smooth curve. Outside the first/last stop the gradient holds those
  /// colours, exactly as before.
  static (List<Color>, List<double>) smooth(
    List<Color> colors, [
    List<double>? stops,
  ]) {
    final n = colors.length;
    final xs =
        stops ?? [for (var i = 0; i < n; i++) n == 1 ? 0.0 : i / (n - 1)];
    if (n < 2) return (colors, xs);
    double ch(Color c, int k) => switch (k) {
      0 => c.a,
      1 => c.r,
      2 => c.g,
      _ => c.b,
    };
    // Monotone cubic Hermite (Fritsch–Carlson) per channel, with zero
    // tangents at both ends so the fade eases in and out of flat colour.
    final tangents = List.generate(4, (k) {
      final d = [
        for (var i = 0; i < n - 1; i++)
          xs[i + 1] > xs[i]
              ? (ch(colors[i + 1], k) - ch(colors[i], k)) / (xs[i + 1] - xs[i])
              : 0.0,
      ];
      final m = List<double>.filled(n, 0);
      for (var i = 1; i < n - 1; i++) {
        if (d[i - 1] * d[i] > 0) {
          final a = d[i - 1], b = d[i];
          // Harmonic-style mean keeps the curve inside each segment.
          m[i] = 2 * a * b / (a + b);
        }
      }
      return m;
    });
    final outColors = <Color>[];
    final outStops = <double>[];
    for (var i = 0; i < n - 1; i++) {
      final x0 = xs[i], x1 = xs[i + 1], h = x1 - x0;
      for (var j = i == 0 ? 0 : 1; j <= _perSegment; j++) {
        final t = j / _perSegment;
        final t2 = t * t, t3 = t2 * t;
        final h00 = 2 * t3 - 3 * t2 + 1;
        final h10 = t3 - 2 * t2 + t;
        final h01 = -2 * t3 + 3 * t2;
        final h11 = t3 - t2;
        double v(int k) =>
            (h00 * ch(colors[i], k) +
                    h10 * h * tangents[k][i] +
                    h01 * ch(colors[i + 1], k) +
                    h11 * h * tangents[k][i + 1])
                .clamp(0.0, 1.0);
        outColors.add(
          Color.from(alpha: v(0), red: v(1), green: v(2), blue: v(3)),
        );
        outStops.add(x0 + h * t);
      }
    }
    return (outColors, outStops);
  }

  /// A [LinearGradient] whose stops are joined by [smooth].
  static LinearGradient linear({
    AlignmentGeometry begin = Alignment.centerLeft,
    AlignmentGeometry end = Alignment.centerRight,
    required List<Color> colors,
    List<double>? stops,
  }) {
    final (c, s) = smooth(colors, stops);
    return LinearGradient(begin: begin, end: end, colors: c, stops: s);
  }
}

class AppScrims {
  AppScrims._();

  /// Hero and detail left column: artwork fades in from the leading edge.
  /// Built from the active theme's ground so the fade meets the screen
  /// background exactly — a fixed Nocturne ground would leave a blue seam
  /// under every other theme.
  static LinearGradient get edge => AppGradients.linear(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.background,
      AppColors.background.withValues(alpha: 0.93),
      AppColors.background.withValues(alpha: 0.35),
    ],
    stops: const [0.0, 0.42, 1.0],
  );

  /// Card captions and player controls.
  static LinearGradient get bottom => AppGradients.linear(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.background.withValues(alpha: 0),
      AppColors.canvas.withValues(alpha: 0.96),
    ],
    stops: const [0.0, 0.78],
  );

  /// Flat plate behind short labels on unpredictable artwork.
  static Color get chip => AppColors.canvas.withValues(alpha: 0.78);

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
  static bool get crossfadeArtwork =>
      level.index <= MotionLevel.noStagger.index;
  static bool get animatePages => level.index <= MotionLevel.noCrossfade.index;
}

/// The focus treatment, as one paired token. Three stacked signals: the fill
/// steps up an elevation, a 2px accent hairline appears, and a 6px accent
/// spine lands on the leading edge. The spine is the one you read from the
/// sofa. All three are single-pass paints, so the lightweight fallback is
/// simply: keep them and drop [focusScale] and the raised shadow.
class AppFocusTreatment {
  AppFocusTreatment._();

  static Color get idleBorderColor => AppColors.line;
  static const idleBorderWidth = AppShape.borderWidth;
  static Color get idleContainer => AppColors.surface;
  static Color get idleContent => AppColors.ink2;

  static Color get focusedBorderColor => AppColors.accent;
  static const focusedBorderWidth = AppShape.borderWidth;
  static Color get focusedSpineColor => AppColors.accent;
  static const focusedSpineWidth = AppShape.spineWidth;
  static Color get focusedContainer => AppColors.surfaceRaised;
  static Color get focusedContent => AppColors.ink;

  /// Selected but not focused: the spine goes ink, the fill stays put.
  static Color get selectedSpineColor => AppColors.ink;

  static Color get pressedContainer => AppColors.accent900;
  static Color get pressedBorderColor => AppColors.accent700;

  /// Barely perceptible up close, and legible in aggregate across a row.
  /// Dropped entirely in low-power mode.
  static const focusScale = 1.03;

  /// Artwork cards: a frame all the way round instead of a spine.
  static Color get artFrameColor => AppColors.accent;
  static const artFrameWidth = AppShape.artFrameWidth;
}
