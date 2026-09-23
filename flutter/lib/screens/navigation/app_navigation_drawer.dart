import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_auth_api.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../data/settings/app_settings.dart' show RelayEntry;
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/app_state.dart' show SectionGroup;
import '../../sync/relay_protocol.dart' show RelayHealth;
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/digital_clock.dart';
import '../home/watch_together_row.dart' show MergedRoom;
import 'rooms_panel.dart';
import 'server_switcher_panel.dart';

const _sectionTypeShow = 'show';

// Screens 01-25's rail: 80 wide, 52x52 items 6 apart, the logo mark 32 du
// with 22 below it, 30 du top/bottom padding, a 40 du avatar at the foot.
const _collapsedRailWidth = AppSpacing.rail;
const _expandedRailWidth = 280.0;
const _railItemSize = 52.0;
const _railItemGap = 6.0;
const _railPaddingY = 30.0;
const _logoSize = 32.0;
const _logoGap = 22.0;
const _avatarSize = 40.0;
const _railIconSize = 26.0;

/// Which rail item is "where you are". Exactly one — or none, for a screen
/// that isn't a rail destination at all. A single value rather than one
/// bool per item is what keeps two items from ever lighting at once.
enum RailDestination { home, search, watchlist, section, settings, none }

/// What the rooms panel (screen 12) needs, bundled so every screen's
/// drawer gets it from one place.
class RoomsPanelData {
  final List<RelayEntry> relays;
  final Map<String, RelayHealth> relayHealth;
  final List<MergedRoom> rooms;
  final String? myRoomId;
  final Set<String> hostedRoomIds;
  final ValueChanged<MergedRoom> onJoin;
  final VoidCallback onRetry;

  const RoomsPanelData({
    required this.relays,
    required this.relayHealth,
    required this.rooms,
    this.myRoomId,
    this.hostedRoomIds = const {},
    required this.onJoin,
    required this.onRetry,
  });
}

/// The persistent rail wrapping every browsing screen. Collapsed it is the
/// design's 80 du icon column; focus entering it expands it to labels
/// (README motion table, "Rail"), and leaving collapses it.
///
/// The rail and the screen beside it are two separate focus scopes, so
/// directional traversal never crosses between them on its own: the rail
/// is entered only by pressing left at the content's leading edge, and left
/// again by pressing right — never by pressing down past a screen's last
/// row, which used to fall into whichever rail item was geometrically
/// nearest.
///
/// Also hosts the two panels that open over the current screen: the
/// server switcher (screen 06, from the avatar) and the rooms panel
/// (screen 12, from the Watch Together item or [roomsPanelOpen]).
class AppNavigationDrawer extends StatefulWidget {
  final List<SectionGroup> sectionGroups;
  final String? selectedSectionGroupKey;
  final RailDestination destination;
  final ValueChanged<SectionGroup> onSelectSection;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenSearch;
  final VoidCallback? onOpenWatchlist;
  final RoomsPanelData? rooms;

  /// Lets a screen inside the drawer (Home's "N more rooms ›") open the
  /// rooms panel without owning it. Owned by AppRoot so it survives the
  /// screen underneath changing.
  final ValueNotifier<bool>? roomsPanelOpen;
  final PlexAccount? account;
  final String? versionName;
  final List<ReachableServer> connectedServers;
  final Set<String> disabledServerIds;
  final Future<List<PlexResource>> Function() loadServers;
  final Future<ReachableServer?> Function(PlexResource resource) probeServer;
  final Future<int?> Function(PlexServer server) loadLibraryCount;
  final void Function(PlexResource resource, bool enabled) onToggleServer;
  final Widget child;

  const AppNavigationDrawer({
    super.key,
    required this.sectionGroups,
    this.selectedSectionGroupKey,
    required this.destination,
    required this.onSelectSection,
    required this.onOpenSettings,
    required this.onOpenHome,
    required this.onOpenSearch,
    this.onOpenWatchlist,
    this.rooms,
    this.roomsPanelOpen,
    this.account,
    this.versionName,
    required this.connectedServers,
    required this.disabledServerIds,
    required this.loadServers,
    required this.probeServer,
    required this.loadLibraryCount,
    required this.onToggleServer,
    required this.child,
  });

  @override
  State<AppNavigationDrawer> createState() => _AppNavigationDrawerState();
}

class _AppNavigationDrawerState extends State<AppNavigationDrawer> {
  bool _expanded = false;
  // Set the instant a rail item is clicked, cleared the next time the rail's
  // focus state actually changes. Selecting takes a beat to load the new
  // screen — during that beat focus is still genuinely on the clicked item,
  // which would otherwise leave the rail visibly expanded the whole time.
  bool _forceCollapsed = false;
  bool _showServerSwitcher = false;
  final _contentScope = FocusScopeNode(debugLabel: 'nav-content');
  final _railScope = FocusScopeNode(debugLabel: 'nav-rail');
  final _avatarFocusNode = FocusNode(debugLabel: 'nav-rail-avatar');
  final _homeItemFocusNode = FocusNode(debugLabel: 'nav-rail-home');
  final _searchItemFocusNode = FocusNode(debugLabel: 'nav-rail-search');
  final _watchlistItemFocusNode = FocusNode(debugLabel: 'nav-rail-watchlist');
  final _roomsItemFocusNode = FocusNode(debugLabel: 'nav-rail-rooms');
  final _settingsItemFocusNode = FocusNode(debugLabel: 'nav-rail-settings');
  final Map<String, FocusNode> _sectionFocusNodes = {};

  bool get _roomsOpen => widget.roomsPanelOpen?.value ?? false;

  @override
  void initState() {
    super.initState();
    _railScope.addListener(_handleRailFocusChange);
    widget.roomsPanelOpen?.addListener(_handleRoomsPanelChange);
  }

  @override
  void didUpdateWidget(covariant AppNavigationDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomsPanelOpen != widget.roomsPanelOpen) {
      oldWidget.roomsPanelOpen?.removeListener(_handleRoomsPanelChange);
      widget.roomsPanelOpen?.addListener(_handleRoomsPanelChange);
    }
  }

  void _handleRoomsPanelChange() {
    if (!mounted) return;
    setState(() => _forceCollapsed = true);
  }

  FocusNode _sectionNode(SectionGroup section) =>
      _sectionFocusNodes.putIfAbsent(section.key, () => FocusNode(debugLabel: 'nav-rail-section-${section.key}'));

  FocusNode get _currentDestinationNode {
    if (_roomsOpen) return _roomsItemFocusNode;
    switch (widget.destination) {
      case RailDestination.settings:
        return _settingsItemFocusNode;
      case RailDestination.search:
        return _searchItemFocusNode;
      case RailDestination.watchlist:
        return _watchlistItemFocusNode;
      case RailDestination.section:
        final key = widget.selectedSectionGroupKey;
        final match = widget.sectionGroups.where((s) => s.key == key).firstOrNull;
        if (match != null) return _sectionNode(match);
        return _homeItemFocusNode;
      case RailDestination.home:
      case RailDestination.none:
        return _homeItemFocusNode;
    }
  }

  List<FocusNode> get _orderedRailFocusNodes => [
    _homeItemFocusNode,
    _searchItemFocusNode,
    _watchlistItemFocusNode,
    for (final section in widget.sectionGroups) _sectionNode(section),
    _roomsItemFocusNode,
    _settingsItemFocusNode,
    _avatarFocusNode,
  ];

  // Up/down walk the rail's own order explicitly: the Spacer between the
  // sections and Settings is a real geometric gap, and nearest-neighbour
  // traversal would happily skip across it. Right leaves for the screen.
  KeyEventResult _handleRailKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
    if (key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }

    final ordered = _orderedRailFocusNodes;
    final currentIndex = ordered.indexWhere((n) => n.hasFocus);
    if (currentIndex == -1) return KeyEventResult.ignored;
    final nextIndex = currentIndex + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
    if (nextIndex >= 0 && nextIndex < ordered.length) {
      final target = ordered[nextIndex];
      target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (targetContext.mounted) {
            Scrollable.ensureVisible(targetContext, duration: AppMotion.railSlide);
          }
        });
      }
    }
    return KeyEventResult.handled;
  }

  // Left at the screen's leading edge is the only way into the rail. Any
  // widget inside the screen that handles left itself (a row scrolling
  // back, a keyboard) sees the key first; this only runs when nothing did.
  KeyEventResult _handleContentKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_contentScope.hasFocus) return KeyEventResult.ignored;
    if (primary.focusInDirection(TraversalDirection.left)) return KeyEventResult.handled;
    // A held key must not tumble out of a row into the rail.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    _currentDestinationNode.requestFocus();
    return KeyEventResult.handled;
  }

  void _focusContent() {
    final remembered = _contentScope.focusedChild;
    if (remembered != null && remembered.context != null && remembered.canRequestFocus) {
      remembered.requestFocus();
      return;
    }
    // Nothing remembered (the screen changed under the rail): the first
    // focusable in the screen, top-left first.
    final candidates = _contentScope.traversalDescendants
        .where((n) => n.canRequestFocus && n.context != null && !n.skipTraversal)
        .toList();
    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      final ra = a.rect, rb = b.rect;
      final dy = ra.top.compareTo(rb.top);
      return dy != 0 ? dy : ra.left.compareTo(rb.left);
    });
    candidates.first.requestFocus();
  }

  void _handleRailFocusChange() {
    if (!mounted) return;
    final hasFocus = _railScope.hasFocus;
    final wasExpanded = _expanded;
    _forceCollapsed = false;
    if (hasFocus && !wasExpanded) {
      // Entering the rail lands on the item for the screen actually
      // showing, not on whatever the scope last remembered.
      final target = _currentDestinationNode;
      if (!target.hasFocus && !_avatarFocusNode.hasFocus) target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (targetContext.mounted) {
            Scrollable.ensureVisible(targetContext, duration: AppMotion.railSlide);
          }
        });
      }
    }
    if (_expanded != hasFocus) setState(() => _expanded = hasFocus);
  }

  void _handleSelect(VoidCallback action) {
    setState(() => _forceCollapsed = true);
    widget.roomsPanelOpen?.value = false;
    action();
  }

  void _openServerSwitcher() {
    widget.roomsPanelOpen?.value = false;
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

  void _openRooms() {
    setState(() {
      _forceCollapsed = true;
      _showServerSwitcher = false;
    });
    widget.roomsPanelOpen?.value = true;
  }

  void _closeRooms() {
    widget.roomsPanelOpen?.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusContent();
    });
  }

  @override
  void dispose() {
    widget.roomsPanelOpen?.removeListener(_handleRoomsPanelChange);
    _railScope.removeListener(_handleRailFocusChange);
    _railScope.dispose();
    _contentScope.dispose();
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

  bool _isSelected(RailDestination d) =>
      !_roomsOpen && !_showServerSwitcher && widget.destination == d;

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded && !_forceCollapsed;
    final rooms = widget.rooms;
    // expand: the panels below are non-positioned children, and a closed
    // one is an empty box — a loose Stack would size itself to that.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(left: _collapsedRailWidth.du(context)),
            child: FocusScope(
              node: _contentScope,
              onKeyEvent: _handleContentKeyEvent,
              child: widget.child,
            ),
          ),
        ),
        Positioned(
          top: 20.du(context),
          right: AppSpacing.xxl.du(context),
          child: const DigitalClock(),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: AnimatedContainer(
            duration: AppMotion.railSlide,
            curve: AppMotion.enter,
            width: (expanded ? _expandedRailWidth : _collapsedRailWidth).du(context),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              border: Border(right: BorderSide(color: AppColors.line, width: 1.du(context))),
              boxShadow: expanded ? AppElevation.overlay : AppElevation.surface,
            ),
            child: FocusScope(
              node: _railScope,
              onKeyEvent: _handleRailKeyEvent,
              child: Padding(
                // (80 - 52) / 2 = 14 either side, so a collapsed item sits
                // centred in the rail and its icon centred in the item.
                padding: EdgeInsets.symmetric(
                  vertical: _railPaddingY.du(context),
                  horizontal: ((_collapsedRailWidth - _railItemSize) / 2).du(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _LogoMark(),
                    SizedBox(height: _logoGap.du(context)),
                    Expanded(
                      // Scrollable so a household with many libraries
                      // degrades gracefully instead of overflowing.
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final item in [
                              _SidebarItem(
                                icon: PhosphorIconsRegular.house,
                                selectedIcon: PhosphorIconsFill.house,
                                label: 'Home',
                                selected: _isSelected(RailDestination.home),
                                expanded: expanded,
                                onClick: () => _handleSelect(widget.onOpenHome),
                                focusNode: _homeItemFocusNode,
                              ),
                              _SidebarItem(
                                icon: PhosphorIconsRegular.magnifyingGlass,
                                selectedIcon: PhosphorIconsFill.magnifyingGlass,
                                label: 'Search',
                                selected: _isSelected(RailDestination.search),
                                expanded: expanded,
                                onClick: () => _handleSelect(widget.onOpenSearch),
                                focusNode: _searchItemFocusNode,
                              ),
                              _SidebarItem(
                                icon: PhosphorIconsRegular.bookmarkSimple,
                                selectedIcon: PhosphorIconsFill.bookmarkSimple,
                                label: 'Watchlist',
                                selected: _isSelected(RailDestination.watchlist),
                                expanded: expanded,
                                onClick: () {
                                  final open = widget.onOpenWatchlist;
                                  if (open != null) _handleSelect(open);
                                },
                                focusNode: _watchlistItemFocusNode,
                              ),
                              for (final section in widget.sectionGroups)
                                _SidebarItem(
                                  key: ValueKey(section.key),
                                  icon: section.type == _sectionTypeShow
                                      ? PhosphorIconsRegular.televisionSimple
                                      : PhosphorIconsRegular.filmSlate,
                                  selectedIcon: section.type == _sectionTypeShow
                                      ? PhosphorIconsFill.televisionSimple
                                      : PhosphorIconsFill.filmSlate,
                                  label: section.title,
                                  selected: _isSelected(RailDestination.section) &&
                                      section.key == widget.selectedSectionGroupKey,
                                  expanded: expanded,
                                  onClick: () => _handleSelect(() => widget.onSelectSection(section)),
                                  focusNode: _sectionNode(section),
                                ),
                              _SidebarItem(
                                icon: PhosphorIconsRegular.usersThree,
                                selectedIcon: PhosphorIconsFill.usersThree,
                                label: 'Watch Together',
                                selected: _roomsOpen,
                                expanded: expanded,
                                enabled: rooms != null,
                                onClick: _openRooms,
                                focusNode: _roomsItemFocusNode,
                              ),
                            ]) ...[item, SizedBox(height: _railItemGap.du(context))],
                          ],
                        ),
                      ),
                    ),
                    _SidebarItem(
                      icon: PhosphorIconsRegular.gear,
                      selectedIcon: PhosphorIconsFill.gear,
                      label: 'Settings',
                      selected: _isSelected(RailDestination.settings),
                      expanded: expanded,
                      onClick: () => _handleSelect(widget.onOpenSettings),
                      focusNode: _settingsItemFocusNode,
                    ),
                    SizedBox(height: 10.du(context)),
                    _UserAvatarItem(
                      account: widget.account,
                      expanded: expanded,
                      selected: _showServerSwitcher,
                      focusNode: _avatarFocusNode,
                      onClick: _openServerSwitcher,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showServerSwitcher)
          ServerSwitcherPanel(
            account: widget.account,
            connectedServers: widget.connectedServers,
            disabledServerIds: widget.disabledServerIds,
            sectionGroups: widget.sectionGroups,
            selectedSectionGroupKey: widget.selectedSectionGroupKey,
            loadServers: widget.loadServers,
            probeServer: widget.probeServer,
            loadLibraryCount: widget.loadLibraryCount,
            onSelectSection: (section) => _handleSelect(() => widget.onSelectSection(section)),
            onToggleServer: widget.onToggleServer,
            onClose: _closeServerSwitcher,
          ),
        if (rooms != null && widget.roomsPanelOpen != null)
          ValueListenableBuilder<bool>(
            valueListenable: widget.roomsPanelOpen!,
            builder: (context, open, _) => open
                ? RoomsPanel(
                    relays: rooms.relays,
                    relayHealth: rooms.relayHealth,
                    rooms: rooms.rooms,
                    myRoomId: rooms.myRoomId,
                    hostedRoomIds: rooms.hostedRoomIds,
                    onJoin: (room) {
                      widget.roomsPanelOpen!.value = false;
                      rooms.onJoin(room);
                    },
                    onRetry: rooms.onRetry,
                    onClose: _closeRooms,
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// The Reelay mark from the design: two offset rounded bars, accent over
/// ink, in a 46-unit box drawn at 32 du. Painted rather than an image so
/// it follows the theme's accent and ink.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: _logoSize.du(context),
        child: CustomPaint(painter: _LogoPainter(accent: AppColors.accent, ink: AppColors.ink)),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color accent;
  final Color ink;

  const _LogoPainter({required this.accent, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 46;
    final r = Radius.circular(4 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5 * u, 9 * u, 36 * u, 12 * u), r), Paint()..color = accent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(5 * u, 25 * u, 22 * u, 12 * u), r), Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.accent != accent || old.ink != ink;
}

RoundedRectangleBorder _railItemShape(BuildContext context) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
);
SurfaceColors get _railItemColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink4,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _railItemBorder => SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
  selectedSpine: SurfaceBorderSide.solid(AppColors.accent, width: AppSpacing.xs),
);

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool expanded;
  final bool enabled;
  final VoidCallback onClick;
  final FocusNode? focusNode;

  const _SidebarItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.expanded,
    this.enabled = true,
    required this.onClick,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    // The icon keeps the same x whether collapsed or expanded — centred in
    // the 52 du collapsed item — so expanding only reveals the label.
    final iconInset = ((_railItemSize - _railIconSize) / 2).du(context);
    return SizedBox(
      height: _railItemSize.du(context),
      child: FocusableSurface(
        onClick: onClick,
        enabled: enabled,
        selected: selected,
        focusNode: focusNode,
        shape: _railItemShape(context),
        colors: _railItemColors,
        border: _railItemBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: iconInset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(selected ? selectedIcon : icon, size: _railIconSize),
              Flexible(
                child: ClipRect(
                  child: AnimatedSize(
                    duration: AppMotion.railSlide,
                    curve: AppMotion.enter,
                    child: expanded
                        ? Padding(
                            padding: EdgeInsetsDirectional.only(start: AppSpacing.lg.du(context), end: AppSpacing.md.du(context)),
                            child: AppText(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final size = _avatarSize.du(context);
    final inset = ((_railItemSize - _avatarSize) / 2).du(context);
    return SizedBox(
      height: _railItemSize.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _railItemShape(context),
        colors: _railItemColors,
        border: _railItemBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: inset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceOverlay),
                alignment: Alignment.center,
                child: thumb != null
                    ? ClipOval(child: Image.network(thumb, width: size, height: size, fit: BoxFit.cover))
                    : AppText(
                        (account?.username.isNotEmpty == true ? account!.username[0] : '?').toUpperCase(),
                        style: AppTypography.label,
                        color: AppColors.ink,
                      ),
              ),
              Flexible(
                child: ClipRect(
                  child: AnimatedSize(
                    duration: AppMotion.railSlide,
                    curve: AppMotion.enter,
                    child: expanded
                        ? Padding(
                            padding: EdgeInsetsDirectional.only(start: AppSpacing.lg.du(context), end: AppSpacing.md.du(context)),
                            child: AppText(account?.username ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
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
