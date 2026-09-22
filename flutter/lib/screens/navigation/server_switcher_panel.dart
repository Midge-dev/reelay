import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_auth_api.dart' show PlexAccount;
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart'
    show ReachableServer, ServerReachability;
import '../../focus/back_handler.dart';
import '../../kit/card.dart';
import '../../kit/filter_chip.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/jellyfin_coming_soon_row.dart';

const _panelWidth = 820.0;
const _railWidth = 80.0;
const _rowMinHeight = 96.0;

class _ServerRow {
  final PlexResource resource;
  bool loading = true;
  ServerReachability? reachability;
  int? libraryCount;

  _ServerRow(this.resource);
}

/// Ports screen 06 of the Nocturne handoff — a panel over the current
/// screen, not a new page, opened from the rail's avatar. Plex only for
/// now (see the disabled Jellyfin row below); real multi-server support —
/// listing every server the account can see, probing which path answers
/// (direct before relay, screen 06's Local/Relayed/Unreachable) — already
/// existed for the initial-connect flow (PlexResourcesApi.connectToResource)
/// and is reused here, not reinvented.
class ServerSwitcherPanel extends StatefulWidget {
  final PlexAccount? account;
  final PlexServer currentServer;
  final List<PlexSection> sections;
  final String? selectedSectionKey;
  final Future<List<PlexResource>> Function() loadServers;
  final Future<ReachableServer?> Function(PlexResource resource) probeServer;
  final Future<int?> Function(PlexServer server) loadLibraryCount;
  final ValueChanged<PlexSection> onSelectSection;
  final ValueChanged<PlexResource> onSwitchServer;
  final VoidCallback onClose;

  const ServerSwitcherPanel({
    super.key,
    this.account,
    required this.currentServer,
    required this.sections,
    this.selectedSectionKey,
    required this.loadServers,
    required this.probeServer,
    required this.loadLibraryCount,
    required this.onSelectSection,
    required this.onSwitchServer,
    required this.onClose,
  });

  @override
  State<ServerSwitcherPanel> createState() => _ServerSwitcherPanelState();
}

class _ServerSwitcherPanelState extends State<ServerSwitcherPanel> {
  final _firstFocus = FocusNode(debugLabel: 'server-switcher-first');
  List<_ServerRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<PlexResource> resources;
    try {
      resources = await widget.loadServers();
    } catch (_) {
      resources = const [];
    }
    if (!mounted) return;
    final rows = resources.map(_ServerRow.new).toList();
    setState(() => _rows = rows);
    // _firstFocus is only actually attached to a row once _rows is
    // non-empty — requesting focus any earlier (e.g. from initState) would
    // target a FocusNode not yet mounted to anything on screen.
    if (rows.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstFocus.requestFocus();
      });
    }
    for (final row in rows) {
      _probeRow(row);
    }
  }

  Future<void> _probeRow(_ServerRow row) async {
    // The active server's reachability and library count are already
    // known — no need to re-probe or refetch either.
    if (row.resource.name == widget.currentServer.name) {
      setState(() {
        row.loading = false;
        row.reachability = ServerReachability.local;
        row.libraryCount = widget.sections.length;
      });
      return;
    }
    ReachableServer? reached;
    try {
      reached = await widget.probeServer(row.resource);
    } catch (_) {
      reached = null;
    }
    if (!mounted) return;
    if (reached == null) {
      setState(() {
        row.loading = false;
        row.reachability = ServerReachability.unreachable;
      });
      return;
    }
    int? count;
    try {
      count = await widget.loadLibraryCount(reached.server);
    } catch (_) {
      count = null;
    }
    if (!mounted) return;
    setState(() {
      row.loading = false;
      row.reachability = reached!.reachability;
      row.libraryCount = count;
    });
  }

  void _selectSection(PlexSection section) {
    widget.onSelectSection(section);
    widget.onClose();
  }

  // The panel is an overlay, not a new page — D-pad navigation should stay
  // inside it while it's open rather than leaking UP into the nav rail
  // behind it (same class of hazard as MaxSeatsMenu/the hero's action row).
  // Back (not UP) is how you leave; see BackHandler above. Only trapped
  // when the *first* row actually has focus — this Focus wraps every row,
  // not just the first, so an unconditional trap here would also swallow
  // ordinary up-navigation between rows further down the list.
  KeyEventResult _trapUp(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _firstFocus.hasFocus) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.account?.username;
    return Stack(
      children: [
        Positioned.fill(
          left: _railWidth.du(context),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: ColoredBox(color: AppScrims.dialog),
          ),
        ),
        Positioned(
          left: _railWidth.du(context),
          top: 0,
          bottom: 0,
          width: _panelWidth.du(context),
          child: BackHandler(
            onBack: widget.onClose,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(right: BorderSide(color: AppColors.line)),
                boxShadow: AppElevation.overlay,
              ),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20.du(context),
                          height: 2.du(context),
                          color: AppColors.accent,
                        ),
                        SizedBox(width: AppSpacing.md.du(context)),
                        AppText('SERVERS', style: AppTypography.micro),
                      ],
                    ),
                    SizedBox(height: AppSpacing.sm.du(context)),
                    AppText(
                      username != null
                          ? "Where $username is watching from"
                          : 'Choose a server',
                      style: AppTypography.title2,
                    ),
                    SizedBox(height: AppSpacing.xl.du(context)),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        onKeyEvent: _trapUp,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (index, row) in _rows.indexed) ...[
                                _ServerResultRow(
                                  row: row,
                                  selected:
                                      row.resource.name ==
                                      widget.currentServer.name,
                                  focusNode: index == 0 ? _firstFocus : null,
                                  onClick: () =>
                                      widget.onSwitchServer(row.resource),
                                ),
                                SizedBox(height: AppSpacing.md.du(context)),
                              ],
                              const JellyfinComingSoonRow(),
                              SizedBox(height: AppSpacing.xl.du(context)),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: AppColors.line),
                                  ),
                                ),
                              ),
                              SizedBox(height: AppSpacing.xl.du(context)),
                              AppText(
                                'LIBRARIES ON ${widget.currentServer.name.toUpperCase()}',
                                style: AppTypography.micro,
                              ),
                              SizedBox(height: AppSpacing.lg.du(context)),
                              Wrap(
                                spacing: AppSpacing.md.du(context),
                                runSpacing: AppSpacing.md.du(context),
                                children: [
                                  for (final section in widget.sections)
                                    AppFilterChip(
                                      key: ValueKey(section.key),
                                      selected:
                                          section.key ==
                                          widget.selectedSectionKey,
                                      onClick: () => _selectSection(section),
                                      child: AppText(section.title),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final _rowBorder = SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

class _ServerResultRow extends StatelessWidget {
  final _ServerRow row;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _ServerResultRow({
    required this.row,
    required this.selected,
    this.focusNode,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final unreachable = row.reachability == ServerReachability.unreachable;
    final subtitleParts = <String>[
      'Plex',
      row.resource.owned ? 'Owned' : 'Shared',
      if (row.libraryCount != null)
        '${row.libraryCount} librar${row.libraryCount == 1 ? 'y' : 'ies'}',
    ];

    return Opacity(
      opacity: unreachable ? 0.45 : 1,
      child: AppCard(
        onClick: onClick,
        enabled: !unreachable,
        selected: selected,
        focusNode: focusNode,
        border: _rowBorder,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowMinHeight.du(context)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl.du(context),
              vertical: AppSpacing.md.du(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const AppIcon(PhosphorIconsRegular.hardDrives, size: 26),
                SizedBox(width: AppSpacing.lg.du(context)),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        row.resource.name,
                        style: selected
                            ? AppTypography.label.copyWith(
                                fontWeight: FontWeight.w500,
                              )
                            : AppTypography.label,
                      ),
                      SizedBox(height: 3.du(context)),
                      AppText(
                        subtitleParts.join(' · '),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.lg.du(context)),
                _ReachabilityBadge(
                  loading: row.loading,
                  reachability: row.reachability,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReachabilityBadge extends StatelessWidget {
  final bool loading;
  final ServerReachability? reachability;

  const _ReachabilityBadge({required this.loading, this.reachability});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AppText('Connecting…', style: AppTypography.caption);
    }
    final (color, label) = switch (reachability) {
      ServerReachability.local => (AppColors.success, 'Local'),
      ServerReachability.relayed => (AppColors.warning, 'Relayed'),
      ServerReachability.unreachable ||
      null => (AppColors.error, 'Unreachable'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.du(context),
          height: 8.du(context),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        SizedBox(width: AppSpacing.sm.du(context)),
        AppText(label, style: AppTypography.caption, color: color),
      ],
    );
  }
}
