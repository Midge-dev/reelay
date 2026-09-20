import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_auth_api.dart';
import '../../data/plex/plex_models.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/digital_clock.dart';

const _sectionTypeShow = 'show';

const _collapsedRailWidth = 80.0;
const _expandedRailWidth = 236.0;
const _railItemHeight = 48.0;
const _railAnimDuration = Duration(milliseconds: 200);

/// Ports ui/navigation/AppNavigationDrawer.kt — the persistent collapsible
/// sidebar wrapping every browsing screen. Auto-expands on D-pad focus
/// (any descendant of the rail having focus, not just the rail itself —
/// same as Compose's focusGroup()+onFocusChanged hasFocus semantics,
/// which Flutter's FocusNode.hasFocus already matches). This is the
/// component the checklist's #1 hazard (overlay-close focus loss to the
/// nav rail) is about — every screen it wraps needs the Stack-overlay
/// pattern already proven in the PoC for any transient UI.
class AppNavigationDrawer extends StatefulWidget {
  final List<PlexSection> sections;
  final String? selectedSectionKey;
  final bool isSettingsSelected;
  final bool isHomeSelected;
  final ValueChanged<PlexSection> onSelectSection;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHome;
  final PlexAccount? account;
  final String? versionName;
  final Widget child;

  const AppNavigationDrawer({
    super.key,
    required this.sections,
    this.selectedSectionKey,
    required this.isSettingsSelected,
    required this.isHomeSelected,
    required this.onSelectSection,
    required this.onOpenSettings,
    required this.onOpenHome,
    this.account,
    this.versionName,
    required this.child,
  });

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  bool _expanded = false;
  final _railFocusNode = FocusNode(debugLabel: 'nav-rail');
  final _homeItemFocusNode = FocusNode(debugLabel: 'nav-rail-home');

  @override
  void initState() {
    super.initState();
    _railFocusNode.addListener(_handleRailFocusChange);
  }

  void _handleRailFocusChange() {
    if (!mounted) return;
    setState(() => _expanded = _railFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _railFocusNode.removeListener(_handleRailFocusChange);
    _railFocusNode.dispose();
    _homeItemFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(left: _collapsedRailWidth),
            child: widget.child,
          ),
        ),
        const Positioned(top: 20, right: 32, child: DigitalClock()),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: AnimatedContainer(
            duration: _railAnimDuration,
            width: _expanded ? _expandedRailWidth : _collapsedRailWidth,
            color: AppColors.surface,
            child: Stack(
              children: [
                Focus(
                  focusNode: _railFocusNode,
                  skipTraversal: true,
                  canRequestFocus: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _UserAvatarItem(account: widget.account, expanded: _expanded),
                        const SizedBox(height: 8),
                        _SidebarItem(
                          icon: Icons.home,
                          label: 'Home',
                          selected: widget.isHomeSelected,
                          expanded: _expanded,
                          onClick: widget.onOpenHome,
                          focusNode: _homeItemFocusNode,
                        ),
                        const SizedBox(height: 4),
                        for (final section in widget.sections) ...[
                          _SidebarItem(
                            icon: section.type == _sectionTypeShow ? Icons.tv : Icons.movie,
                            label: section.title,
                            selected: !widget.isSettingsSelected && !widget.isHomeSelected && section.key == widget.selectedSectionKey,
                            expanded: _expanded,
                            onClick: () => widget.onSelectSection(section),
                          ),
                          const SizedBox(height: 4),
                        ],
                        const Spacer(),
                        _SidebarItem(
                          icon: Icons.settings,
                          label: 'Settings',
                          selected: widget.isSettingsSelected,
                          expanded: _expanded,
                          onClick: widget.onOpenSettings,
                        ),
                        if (widget.versionName != null)
                          ClipRect(
                            child: AnimatedSize(
                              duration: _railAnimDuration,
                              child: _expanded
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 16, top: 8),
                                      child: AppText('v${widget.versionName}', style: AppTypography.bodySmall, color: AppColors.onSurfaceVariant),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(top: 0, bottom: 0, right: 0, child: Container(width: 1, color: AppColors.surfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final _railItemColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.white,
  focusedContainer: AppColors.accent,
  selectedContainer: AppColors.accent.withValues(alpha: 0.35),
);

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onClick;
  final FocusNode? focusNode;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onClick,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _railItemHeight,
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: const StadiumBorder(),
        colors: _railItemColors,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.white, size: 24),
              ClipRect(
                child: AnimatedSize(
                  duration: _railAnimDuration,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: AppText(label, color: AppColors.white),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAvatarItem extends StatelessWidget {
  final PlexAccount? account;
  final bool expanded;

  const _UserAvatarItem({this.account, required this.expanded});

  @override
  Widget build(BuildContext context) {
    final thumb = account?.thumb;
    return SizedBox(
      height: _railItemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.35)),
              alignment: Alignment.center,
              child: thumb != null
                  ? ClipOval(child: Image.network(thumb, width: 40, height: 40, fit: BoxFit.cover))
                  : AppText((account?.username.isNotEmpty == true ? account!.username[0] : '?').toUpperCase(), style: AppTypography.bodyLarge, color: AppColors.white),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: _railAnimDuration,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(left: 14),
                        // TODO: port basicMarquee() for usernames that overflow — deferred polish, not needed for basic functionality.
                        child: AppText(
                          account?.username ?? '',
                          color: AppColors.white,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
