import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../kit/card.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/marquee_text.dart';
import '../../kit/scroll_peek.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

/// Portrait card geometry (DESIGN.md "Card geometry is fixed"): 220x330,
/// caption 12 below, a label line and an optional caption line.
const posterWidth = 220.0;
const posterHeight = 330.0;
const _captionGap = 12.0;

/// Card height including its caption block — what a grid or row reserves
/// per card. Label 26 + 2 + caption 24, +8 because text line boxes round
/// up at fractional scales.
const posterCardExtent = posterHeight + _captionGap + 26 + 2 + 24 + 8;

/// Artwork cards take a frame all the way round instead of a spine — a
/// spine would cover the poster — and the caption steps ink3 -> ink on
/// focus instead of the fill+hairline+spine signal. DESIGN.md non-
/// negotiable #3.
SurfaceBorder get _posterBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(
    AppColors.accent,
    width: AppShape.artFrameWidth,
  ),
  noSpine: true,
);

/// Grid columns for [contentWidth] logical px: counts follow remaining
/// width, sizes follow height (DESIGN.md #5) — computed from the *scaled*
/// card and gutter so a larger UI scale yields fewer columns of the same
/// 220 du poster rather than the same seven columns of shrunken ones.
int posterGridColumns(BuildContext context, double contentWidth) {
  final gutter = AppSpacing.xl.du(context);
  final card = posterWidth.du(context);
  return math.max(1, ((contentWidth + gutter) / (card + gutter)).floor());
}

/// The gap between columns when [columns] fill [contentWidth] edge to edge:
/// cards stay at their fixed 220 du, and the width left over after them
/// goes into the gaps, so the last column ends flush with the header's
/// trailing edge (the search field) as the first starts flush with its
/// leading one. Never tighter than the standard gutter.
double posterGridSpacing(
  BuildContext context,
  int columns,
  double contentWidth,
) {
  final gutter = AppSpacing.xl.du(context);
  if (columns < 2) return gutter;
  final spare = contentWidth - columns * posterWidth.du(context);
  return math.max(gutter, spare / (columns - 1));
}

SliverGridDelegate posterGridDelegate(
  BuildContext context,
  int columns, {
  required double crossAxisSpacing,
}) => SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: columns,
  mainAxisSpacing: AppSpacing.xl.du(context),
  crossAxisSpacing: crossAxisSpacing,
  mainAxisExtent: posterCardExtent.du(context),
);

/// A clip that lets a focused card's 1.03x scale and 3 du frame spill
/// sideways past the grid's own bounds (the cards sit flush with the
/// header above) while still clipping the scrolled-away rows vertically.
class GridSideBleedClipper extends CustomClipper<Rect> {
  final double bleed;

  const GridSideBleedClipper(this.bleed);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-bleed, 0, size.width + bleed, size.height);

  @override
  bool shouldReclip(covariant GridSideBleedClipper old) => old.bleed != bleed;
}

/// The one poster grid every grid screen uses (library, watchlist,
/// collection, filmography): as many 220 du columns as the width holds,
/// spread to span it edge to edge, rowHeadroom/2 above the first row so a
/// focused card's scale isn't clipped, and the scrolled-away edge faded.
class PosterGrid extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  const PosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
  });

  @override
  State<PosterGrid> createState() => _PosterGridState();
}

class _PosterGridState extends State<PosterGrid> {
  ScrollController? _ownController;

  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = posterGridColumns(context, constraints.maxWidth);
        final spacing = posterGridSpacing(
          context,
          columns,
          constraints.maxWidth,
        );
        return ClipRect(
          clipper: GridSideBleedClipper(AppSpacing.safeX.du(context)),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) => EdgeFadeRow(
              axis: Axis.vertical,
              fadeStart: controller.hasClients && controller.offset > 0,
              fadeWidth: posterRowPeekExtent,
              child: child!,
            ),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width:
                    columns * posterWidth.du(context) + (columns - 1) * spacing,
                child: GridView.builder(
                  controller: controller,
                  padding: EdgeInsets.only(
                    top: (AppSpacing.rowHeadroom / 2).du(context),
                    bottom: AppSpacing.safeY.du(context),
                  ),
                  clipBehavior: Clip.none,
                  gridDelegate: posterGridDelegate(
                    context,
                    columns,
                    crossAxisSpacing: spacing,
                  ),
                  itemCount: widget.itemCount,
                  itemBuilder: widget.itemBuilder,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How much of the next row a focused card's grid should leave peeking
/// (and fading) below it — shared with the grid's own EdgeFadeRow so the
/// reserved scroll gap and the visible fade band line up exactly.
const posterRowPeekExtent = 120.0;

/// Shared by CollectionDetailScreen/PersonFilmographyScreen — Kotlin
/// doesn't share a helper between these either (each screen
/// declares its own near-identical `*Poster` composable), but since this
/// is a literal copy-paste in the source, porting it once here avoids
/// tripling the duplication for no reason.
class PosterCard extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback onClick;
  final VoidCallback? onLongClick;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A short label along the poster's foot, on a scrim (DESIGN.md #2) —
  /// screen 20's "Not on your servers".
  final Widget? marker;

  /// Captions a step dimmer — a title you can see but not play here.
  final bool muted;

  /// A second card's edge peeking out behind the poster — screen 19's
  /// collections, so a set of titles never reads as a single one.
  final bool stacked;

  const PosterCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    required this.onClick,
    this.onLongClick,
    this.focusNode,
    this.autofocus = false,
    this.marker,
    this.muted = false,
    this.stacked = false,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'poster-card');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    if (!_focused) return;
    // AppCard's own ensureCardVisible call (see card.dart) only reveals the
    // poster image itself — its RenderObject doesn't extend down to this
    // title below it, which a vertical grid can still leave clipped at the
    // viewport edge even once the image scrolls fully into view. Calling a
    // row-aware reveal again from here, at the whole-card level, includes
    // the title and leaves the next row peeking rather than fully hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        ensureRowVisible(context, peekExtent: posterRowPeekExtent.du(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Align loosens the grid cell's tight incoming constraint — a SizedBox
    // can't override an already-tight constraint from its parent (the same
    // gotcha documented in project_flutter_focus_poc.md), and
    // SliverGridDelegateWithFixedCrossAxisCount always hands each item a
    // tight constraint matching the computed cell size.
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: posterWidth.du(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.stacked)
                  Positioned(
                    left: 10.du(context),
                    right: -10.du(context),
                    top: -6.du(context),
                    height: posterHeight.du(context),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(
                          color: AppColors.line,
                          width: 2.du(context),
                        ),
                        borderRadius: BorderRadius.circular(
                          AppShape.radiusMd.du(context),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: posterHeight.du(context),
                  child: AppCard(
                    onClick: widget.onClick,
                    onLongClick: widget.onLongClick,
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    border: _posterBorder,
                    // This widget's own _handleFocusChange already does a
                    // title-inclusive ensureRowVisible; AppCard's narrower,
                    // image-only default would otherwise fire right after it
                    // (same focus notification, later-registered listener) and
                    // win, undoing the more precise target.
                    ensureVisibleOnFocus: false,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Artwork(imageUrl: widget.imageUrl),
                        if (widget.marker != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: AppScrims.dialog,
                              padding: EdgeInsets.symmetric(
                                horizontal: 14.du(context),
                                vertical: AppSpacing.md.du(context),
                              ),
                              child: widget.marker,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(top: _captionGap.du(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarqueeText(
                    widget.title,
                    active: _focused,
                    style: _focused
                        ? AppTypography.label.copyWith(
                            fontWeight: FontWeight.w500,
                          )
                        : AppTypography.label,
                    color: _focused
                        ? AppColors.ink
                        : (widget.muted ? AppColors.ink3 : AppColors.ink2),
                  ),
                  if (widget.subtitle != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2.du(context)),
                      child: AppText(
                        widget.subtitle!,
                        style: AppTypography.caption,
                        color: _focused
                            ? AppColors.ink2
                            : (widget.muted ? AppColors.ink4 : AppColors.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
