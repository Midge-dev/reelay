import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_auth_api.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/digital_clock.dart';
import 'server_switcher_panel.dart';

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
  final bool isSearchSelected;
  final ValueChanged<PlexSection> onSelectSection;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  // Nullable — screens 20 (Watchlist) and 12 (Rooms panel) don't exist yet.
  // The rail item still renders (spec order: Home, Search, Watchlist,
  // sections, Watch Together, Settings) so the rail itself is complete;
  // wire these up when their destination screens land.
  final VoidCallback? onOpenWatchlist;
  final VoidCallback? onOpenRooms;
  final PlexAccount? account;
  final String? versionName;
  final PlexServer currentServer;
  final Future<List<PlexResource>> Function() loadServers;
  final Future<ReachableServer?> Function(PlexResource resource) probeServer;
  final Future<int?> Function(PlexServer server) loadLibraryCount;
  final ValueChanged<PlexResource> onSwitchServer;
  final Widget child;

  const AppNavigationDrawer({
    super.key,
    required this.sections,
    this.selectedSectionKey,
    required this.isSettingsSelected,
    required this.isHomeSelected,
    this.isSearchSelected = false,
    required this.onSelectSection,
    required this.onOpenSettings,
    required this.onOpenHome,
    required this.onOpenSearch,
    this.onOpenWatchlist,
    this.onOpenRooms,
    this.account,
    this.versionName,
    required this.currentServer,
    required this.loadServers,
    required this.probeServer,
    required this.loadLibraryCount,
    required this.onSwitchServer,
    required this.child,
  });

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  bool _expanded = false;
  // Set the instant a rail item is clicked, cleared the next time the rail's
  // focus state actually changes. Selecting takes a beat to load the new
  // screen (see LoadingSection/LoadingHome) — during that beat, focus is
  // still genuinely sitting on the clicked rail item (nothing in the
  // loading screen is focusable to pull it away), which would otherwise
  // leave the drawer visibly expanded the whole time. This forces the
  // width to collapse right away without waiting for focus to move.
  bool _forceCollapsed = false;
  bool _showServerSwitcher = false;
  final _avatarFocusNode = FocusNode(debugLabel: 'nav-rail-avatar');
  final _railFocusNode = FocusNode(debugLabel: 'nav-rail');
  final _homeItemFocusNode = FocusNode(debugLabel: 'nav-rail-home');
  final _searchItemFocusNode = FocusNode(debugLabel: 'nav-rail-search');
  final _watchlistItemFocusNode = FocusNode(debugLabel: 'nav-rail-watchlist');
  final _roomsItemFocusNode = FocusNode(debugLabel: 'nav-rail-rooms');
  final _settingsItemFocusNode = FocusNode(debugLabel: 'nav-rail-settings');
  late final Map<String, FocusNode> _sectionFocusNodes = {
    for (final section in widget.sections)
      section.key: FocusNode(debugLabel: 'nav-rail-section-${section.key}'),
  };

  @override
  void initState() {
    super.initState();
    _railFocusNode.addListener(_handleRailFocusChange);
  }

  FocusNode get _currentSectionFocusNode {
    if (widget.isSettingsSelected) return _settingsItemFocusNode;
    if (widget.isSearchSelected) return _searchItemFocusNode;
    final key = widget.selectedSectionKey;
    if (!widget.isHomeSelected &&
        key != null &&
        _sectionFocusNodes.containsKey(key))
      return _sectionFocusNodes[key]!;
    return _homeItemFocusNode;
  }

  List<FocusNode> get _orderedRailFocusNodes => [
    _avatarFocusNode,
    _homeItemFocusNode,
    _searchItemFocusNode,
    _watchlistItemFocusNode,
    for (final section in widget.sections) _sectionFocusNodes[section.key]!,
    _roomsItemFocusNode,
    _settingsItemFocusNode,
  ];

  // Home sits at the top of the rail and Settings at the bottom, separated
  // from their nearest section neighbor by a Spacer — a real geometric gap
  // Flutter's default directional traversal measures literally. At either
  // end, a content widget off to the side can end up geometrically closer
  // than the next real rail item across that gap, so UP from Home or DOWN
  // from Settings (and, less obviously, UP from Settings when the nearest
  // section item is still a full Spacer's worth of distance away) can jump
  // straight into content instead of stopping at the rail's own edge.
  // Handling up/down explicitly here — same trap pattern as
  // GenreFilterPanel/MaxSeatsMenu/the on-screen keyboard — makes rail
  // navigation deterministic instead of leaving it to that distance
  // heuristic.
  KeyEventResult _handleRailKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown)
      return KeyEventResult.ignored;

    final ordered = _orderedRailFocusNodes;
    final currentIndex = ordered.indexWhere((n) => n.hasFocus);
    if (currentIndex == -1) return KeyEventResult.ignored;

    final nextIndex =
        currentIndex + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
    if (nextIndex >= 0 && nextIndex < ordered.length) {
      final target = ordered[nextIndex];
      target.requestFocus();
      // The Home/Search/section list now scrolls (see the matching comment
      // below on why) — Settings/the avatar sit outside that Scrollable, so
      // context is null for them and there's nothing to reveal.
      final targetContext = target.context;
      if (targetContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (targetContext.mounted)
            Scrollable.ensureVisible(
              targetContext,
              duration: _railAnimDuration,
            );
        });
      }
    }
    return KeyEventResult.handled;
  }

  void _handleRailFocusChange() {
    if (!mounted) return;
    final hasFocus = _railFocusNode.hasFocus;
    final wasExpanded = _expanded;
    _forceCollapsed = false;
    if (hasFocus && !wasExpanded) {
      // Just entered the rail from content (via LEFT or DOWN past the last
      // row) — land on whichever item matches the section actually on
      // screen rather than wherever default nearest-neighbor traversal
      // happens to place focus (e.g. Settings, purely because it's the
      // rail item geometrically closest to the last focused content row).
      // Redirect synchronously, not via postFrameCallback — this listener
      // itself already runs during FocusManager's pre-build focus-change
      // pass, so a deferred correction would let the wrong target actually
      // paint for a frame first, visible as a jump/flash before snapping
      // to the right one.
      final target = _currentSectionFocusNode;
      target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (targetContext.mounted)
            Scrollable.ensureVisible(
              targetContext,
              duration: _railAnimDuration,
            );
        });
      }
    }
    setState(() => _expanded = hasFocus);
  }

  void _handleSelect(VoidCallback action) {
    setState(() => _forceCollapsed = true);
    action();
  }

  void _openServerSwitcher() {
    setState(() {
      _forceCollapsed = true;
      _showServerSwitcher = true;
    });
  }

  void _closeServerSwitcher() {
    setState(() => _showServerSwitcher = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _avatarFocusNode.requestFocus();
    });
  }

  void _switchServer(PlexResource resource) {
    _closeServerSwitcher();
    widget.onSwitchServer(resource);
  }

  @override
  void dispose() {
    _railFocusNode.removeListener(_handleRailFocusChange);
    _railFocusNode.dispose();
    _avatarFocusNode.dispose();
    _homeItemFocusNode.dispose();
    _searchItemFocusNode.dispose();
    _watchlistItemFocusNode.dispose();
    _roomsItemFocusNode.dispose();
    _settingsItemFocusNode.dispose();
    for (final node in _sectionFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveExpanded = _expanded && !_forceCollapsed;
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
            width: effectiveExpanded ? _expandedRailWidth : _collapsedRailWidth,
            // Reads as floating above the content behind it while open —
            // BoxShadow.lerpList pads the empty/single-shadow lists with a
            // zero-alpha shadow at the same offset/blur, so this still
            // animates smoothly in and out with the width, not a hard cut.
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: effectiveExpanded
                  ? [
                      BoxShadow(
                        color: AppScrims.dialog.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(8, 0),
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              children: [
                Focus(
                  focusNode: _railFocusNode,
                  skipTraversal: true,
                  canRequestFocus: false,
                  onKeyEvent: _handleRailKeyEvent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Scrollable rather than a fixed Column+Spacer — a
                        // household with enough library sections (or, now,
                        // Search added ahead of them) can genuinely exceed
                        // the rail's height; scrolling degrades gracefully
                        // where a fixed list would just overflow off the
                        // bottom of the screen.
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _UserAvatarItem(
                                  account: widget.account,
                                  expanded: effectiveExpanded,
                                  selected: _showServerSwitcher,
                                  focusNode: _avatarFocusNode,
                                  onClick: _openServerSwitcher,
                                ),
                                const SizedBox(height: 8),
                                _SidebarItem(
                                  icon: PhosphorIconsRegular.house,
                                  selectedIcon: PhosphorIconsFill.house,
                                  label: 'Home',
                                  selected: widget.isHomeSelected,
                                  expanded: effectiveExpanded,
                                  onClick: () =>
                                      _handleSelect(widget.onOpenHome),
                                  focusNode: _homeItemFocusNode,
                                ),
                                const SizedBox(height: 4),
                                _SidebarItem(
                                  icon: PhosphorIconsRegular.magnifyingGlass,
                                  selectedIcon:
                                      PhosphorIconsFill.magnifyingGlass,
                                  label: 'Search',
                                  selected: widget.isSearchSelected,
                                  expanded: effectiveExpanded,
                                  onClick: () =>
                                      _handleSelect(widget.onOpenSearch),
                                  focusNode: _searchItemFocusNode,
                                ),
                                const SizedBox(height: 4),
                                _SidebarItem(
                                  icon: PhosphorIconsRegular.bookmarkSimple,
                                  selectedIcon:
                                      PhosphorIconsFill.bookmarkSimple,
                                  label: 'Watchlist',
                                  selected: false,
                                  expanded: effectiveExpanded,
                                  onClick: () {
                                    if (widget.onOpenWatchlist != null)
                                      _handleSelect(widget.onOpenWatchlist!);
                                  },
                                  focusNode: _watchlistItemFocusNode,
                                ),
                                const SizedBox(height: 4),
                                for (final section in widget.sections) ...[
                                  _SidebarItem(
                                    icon: section.type == _sectionTypeShow
                                        ? PhosphorIconsRegular.televisionSimple
                                        : PhosphorIconsRegular.filmSlate,
                                    selectedIcon:
                                        section.type == _sectionTypeShow
                                        ? PhosphorIconsFill.televisionSimple
                                        : PhosphorIconsFill.filmSlate,
                                    label: section.title,
                                    selected:
                                        !widget.isSettingsSelected &&
                                        !widget.isHomeSelected &&
                                        section.key ==
                                            widget.selectedSectionKey,
                                    expanded: effectiveExpanded,
                                    onClick: () => _handleSelect(
                                      () => widget.onSelectSection(section),
                                    ),
                                    focusNode: _sectionFocusNodes[section.key],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                _SidebarItem(
                                  icon: PhosphorIconsRegular.usersThree,
                                  selectedIcon: PhosphorIconsFill.usersThree,
                                  label: 'Watch Together',
                                  selected: false,
                                  expanded: effectiveExpanded,
                                  onClick: () {
                                    if (widget.onOpenRooms != null)
                                      _handleSelect(widget.onOpenRooms!);
                                  },
                                  focusNode: _roomsItemFocusNode,
                                ),
                              ],
                            ),
                          ),
                        ),
                        _SidebarItem(
                          icon: PhosphorIconsRegular.gear,
                          selectedIcon: PhosphorIconsFill.gear,
                          label: 'Settings',
                          selected: widget.isSettingsSelected,
                          expanded: effectiveExpanded,
                          onClick: () => _handleSelect(widget.onOpenSettings),
                          focusNode: _settingsItemFocusNode,
                        ),
                        if (widget.versionName != null)
                          ClipRect(
                            child: AnimatedSize(
                              duration: _railAnimDuration,
                              child: effectiveExpanded
                                  ? Padding(
                                      padding: const EdgeInsets.only(
                                        left: 16,
                                        top: 8,
                                      ),
                                      child: AppText(
                                        'v${widget.versionName}',
                                        style: AppTypography.caption,
                                        color: AppColors.ink3,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: Container(width: 1, color: AppColors.surface),
                ),
              ],
            ),
          ),
        ),
        if (_showServerSwitcher)
          ServerSwitcherPanel(
            account: widget.account,
            currentServer: widget.currentServer,
            sections: widget.sections,
            selectedSectionKey: widget.selectedSectionKey,
            loadServers: widget.loadServers,
            probeServer: widget.probeServer,
            loadLibraryCount: widget.loadLibraryCount,
            onSelectSection: (section) =>
                _handleSelect(() => widget.onSelectSection(section)),
            onSwitchServer: _switchServer,
            onClose: _closeServerSwitcher,
          ),
      ],
    );
  }
}

final _railItemShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd),
);
final _railItemColors = SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink4,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
final _railItemBorder = SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onClick;
  final FocusNode? focusNode;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
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
        shape: _railItemShape,
        colors: _railItemColors,
        border: _railItemBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(selected ? selectedIcon : icon, size: 26),
              // Flexible, not a bare child — the rail's own width and this
              // label's reveal are two independently-animated widths (the
              // AnimatedContainer above and this AnimatedSize), so a frame
              // partway through either transition can briefly ask for more
              // label width than the rail currently has. Flexible lets the
              // label give way at that frame instead of overflowing.
              Flexible(
                child: ClipRect(
                  child: AnimatedSize(
                    duration: _railAnimDuration,
                    child: expanded
                        ? Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: AppText(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
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
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _UserAvatarItem({
    this.account,
    required this.expanded,
    required this.selected,
    this.focusNode,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = account?.thumb;
    return SizedBox(
      height: _railItemHeight,
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _railItemShape,
        colors: _railItemColors,
        border: _railItemBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceOverlay,
                ),
                alignment: Alignment.center,
                child: thumb != null
                    ? ClipOval(
                        child: Image.network(
                          thumb,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : AppText(
                        (account?.username.isNotEmpty == true
                                ? account!.username[0]
                                : '?')
                            .toUpperCase(),
                        style: AppTypography.body,
                        color: AppColors.inkOnArt,
                      ),
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
      ),
    );
  }
}
