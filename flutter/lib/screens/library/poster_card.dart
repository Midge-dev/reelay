import 'package:flutter/widgets.dart';

import '../../kit/card.dart';
import '../../kit/marquee_text.dart';
import '../../kit/scroll_peek.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';

const _posterWidth = 160.0;
const _posterAspectRatio = 2 / 3;

/// Artwork cards take a frame all the way round instead of a spine — a
/// spine would cover the poster — and the caption steps ink3 -> ink on
/// focus instead of the fill+hairline+spine signal. DESIGN.md non-
/// negotiable #3.
final _posterBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(
    AppColors.accent,
    width: AppShape.artFrameWidth,
  ),
  noSpine: true,
);

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
  final int staggerDelayMs;

  const PosterCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    required this.onClick,
    this.onLongClick,
    this.focusNode,
    this.autofocus = false,
    this.staggerDelayMs = 0,
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
      if (mounted) ensureRowVisible(context, peekExtent: posterRowPeekExtent);
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
        width: _posterWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _posterAspectRatio,
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
                child: SizedBox.expand(
                  child: Artwork(
                    imageUrl: widget.imageUrl,
                    staggerDelayMs: widget.staggerDelayMs,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
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
                    color: _focused ? AppColors.ink : AppColors.ink2,
                  ),
                  if (widget.subtitle != null)
                    AppText(
                      widget.subtitle!,
                      style: AppTypography.caption,
                      color: _focused ? AppColors.ink : AppColors.ink3,
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
