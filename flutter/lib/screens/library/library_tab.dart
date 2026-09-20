import 'package:flutter/widgets.dart';

import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _tabHeight = 48.0;
const _tabShape = RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)));
final _tabColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.onSurfaceVariant,
  focusedContainer: AppColors.accent,
  focusedContent: AppColors.white,
  selectedContainer: AppColors.background,
  selectedContent: AppColors.onSurface,
);
const _tabBorder = SurfaceBorder(focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient));
// A selected tab draws its own top-only indicator bar instead of
// FocusableSurface's usual full-perimeter focus border — that border is a
// foreground painter that traces the whole shape, which would either fight
// with the bar (mostly occluding it) or, if recolored, ring the entire tab
// in white when only a top accent is wanted. Suppressing it here (no
// `focused` side) and switching the bar's own color on focus gets a
// top-only highlight with nothing competing for the same pixels.
const _selectedTabBorder = SurfaceBorder();
const _tabGlow = SurfaceGlow(focusedColor: AppColors.accentGlow);

/// Ports ui/library/LibraryScreen.kt's private `LibraryTab`.
class LibraryTab extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onClick;
  final FocusNode? focusNode;

  const LibraryTab({super.key, required this.label, required this.selected, required this.onClick, this.focusNode});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // Focused normally reads via a solid purple fill (focusedContainer) —
    // against that, the bar's usual purple gradient nearly disappears, so it
    // switches to solid white while focused.
    final barColors = _focused ? const [AppColors.white, AppColors.white] : const [AppColors.accentGlow, AppColors.accent];

    return SizedBox(
      height: _tabHeight,
      child: FocusableSurface(
        onClick: widget.onClick,
        selected: selected,
        focusNode: widget.focusNode,
        shape: _tabShape,
        colors: _tabColors,
        border: selected ? _selectedTabBorder : _tabBorder,
        glow: _tabGlow,
        onFocusChange: (focused) => setState(() => _focused = focused),
        // FocusableSurface centers its child by default (Align), which would
        // otherwise center this Stack's own (shorter) intrinsic height as a
        // block within the tab — leaving a gap above the indicator bar
        // instead of it sitting flush at the tab's true top edge. Forcing
        // height (not width, which must stay intrinsic — this row's parent
        // gives each tab unbounded width via a shrink-wrapped Row) makes the
        // Stack fill the tab exactly, so Positioned(top: 0) means the real top.
        child: SizedBox(
          height: _tabHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (selected)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: barColors),
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(top: selected ? 3 : 0, left: 26, right: 26),
                child: AppText(widget.label, style: selected ? AppTypography.titleMedium : AppTypography.bodyLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
