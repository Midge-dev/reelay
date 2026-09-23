import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart';
import '../../data/settings/app_settings.dart';
import '../../kit/focusable_surface.dart';
import '../../focus/back_handler.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../pairing/pairing_server.dart';
import '../../state/data_providers.dart';
import '../../sync/relay_directory_api.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/loading_screen.dart';
import '../common/relay_status.dart';
import '../profiles/add_profile_dialog.dart';
import 'appearance_screen.dart';
import 'max_seats_menu.dart';
import 'relay_settings_pane.dart';

const _uuid = Uuid();

/// Screen 08 — Settings. Two columns: groups on the left holding
/// selection (moving focus through them switches the pane), the pane on
/// the right taking focus only when you cross into it. Every setting states
/// its current value in its row, so nothing needs opening to be read, and
/// every change applies and persists the moment it's made — there is no
/// Save. Server on/off is the one change that needs the hub to reconnect,
/// which happens on the way out (see [SettingsScreen.onServersChanged]).
/// MaxSeatsMenu keeps its explicit focus trap (checklist #8).
class SettingsScreen extends ConsumerStatefulWidget {
  final String accountToken;
  final String clientIdentifier;
  final String? hint;
  final String? versionName;
  final VoidCallback onBack;

  /// Leaving Settings after turning a server on or off — the hub has to
  /// reconnect to pick the change up (see AppRootController.connect).
  final VoidCallback onServersChanged;

  const SettingsScreen({
    super.key,
    required this.accountToken,
    required this.clientIdentifier,
    this.hint,
    this.versionName,
    required this.onBack,
    required this.onServersChanged,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  List<PlexResource> _sources = const [];
  bool _sourcesLoaded = false;
  String? _sourcesError;

  bool _showingRelaySettings = false;
  bool _maxSeatsMenuExpanded = false;
  bool _showingAddProfile = false;
  late _Group _group = widget.hint != null
      ? _Group.watchTogether
      : _Group.watchTogether;
  final Map<_Group, FocusNode> _groupFocus = {
    for (final g in _Group.values)
      g: FocusNode(debugLabel: 'settings-group-${g.name}'),
  };
  bool _serversChanged = false;

  PairingServer? _pairingServer;
  String? _pairingUrl;
  String? _pairingError;
  String? _editingRelayId;
  String? _testingRelayName;
  RelayStatus _testStatus = RelayStatus.silent;
  Timer? _silentTimer;

  final _relayDirectoryApi = RelayDirectoryApi();
  Map<String, RelayReachability?> _relayStatuses = {};

  final _firstSourceFocus = FocusNode(debugLabel: 'settings-first-source');
  final _relaySettingsEntryFocus = FocusNode(
    debugLabel: 'relay-settings-entry',
  );
  final _relaySettingsBackFocus = FocusNode(debugLabel: 'relay-settings-back');
  final _appearanceEntryFocus = FocusNode(debugLabel: 'appearance-entry');
  final _maxHostSeatsFocus = FocusNode(debugLabel: 'max-host-seats');
  final _addRelayFocus = FocusNode(debugLabel: 'add-relay');
  final _cancelPairingFocus = FocusNode(debugLabel: 'cancel-pairing');
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The settings content (including every focusable row) doesn't exist in
    // the tree until both loads resolve — the nav rail's Settings item
    // otherwise keeps focus forever once this screen mounts, since nothing
    // inside it ever claims focus on its own. Same root cause as the
    // Seasons/Relay-settings "opens the nav drawer" bugs: any screen swap
    // needs an explicit focus request, autofocus/default traversal won't
    // steal it from an already-focused ancestor.
    Future.wait([_loadSettings(), _loadSources()]).then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _groupFocus[_group]!.requestFocus();
      });
    });
  }

  Future<void> _loadSettings() async {
    final settings = await ref.read(settingsStoreProvider).observe().first;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loaded = true;
    });
    _refreshRelayStatuses();
  }

  Future<void> _loadSources() async {
    try {
      final sources = await PlexResourcesApi(widget.clientIdentifier)
          .listServers(widget.accountToken);
      if (!mounted) return;
      setState(() => _sources = sources);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sourcesError = '$e');
    } finally {
      if (mounted) setState(() => _sourcesLoaded = true);
    }
  }

  Future<void> _refreshRelayStatuses() async {
    final relays = _settings.relays;
    setState(() => _relayStatuses = {for (final r in relays) r.id: null});
    for (final entry in relays) {
      final reachable = await _relayDirectoryApi.testReachable(entry.url);
      final count = reachable
          ? (await _relayDirectoryApi.listRooms(entry.url)).length
          : 0;
      if (!mounted) return;
      setState(
        () => _relayStatuses = {
          ..._relayStatuses,
          entry.id: RelayReachability(reachable, count),
        },
      );
    }
  }

  @override
  void dispose() {
    _pairingServer?.stop();
    _silentTimer?.cancel();
    _firstSourceFocus.dispose();
    _relaySettingsEntryFocus.dispose();
    _relaySettingsBackFocus.dispose();
    _appearanceEntryFocus.dispose();
    _maxHostSeatsFocus.dispose();
    _addRelayFocus.dispose();
    _cancelPairingFocus.dispose();
    _scrollController.dispose();
    for (final node in _groupFocus.values) {
      node.dispose();
    }
    _paneNode.dispose();
    super.dispose();
  }

  Future<void> _persistRelays(List<RelayEntry> newRelays) async {
    setState(() => _settings = _settings.copyWith(relays: newRelays));
    final store = ref.read(settingsStoreProvider);
    final persisted = await store.observe().first;
    await store.save(persisted.copyWith(relays: newRelays));
  }

  void _startPairing({
    String? editingId,
    String prefillNickname = '',
    String prefillUrl = '',
  }) async {
    setState(() {
      _pairingError = null;
      _editingRelayId = editingId;
    });
    final server = PairingServer(
      prefillNickname: prefillNickname,
      prefillUrl: prefillUrl,
      onSubmitted: (nickname, url) =>
          _onPairingSubmitted(editingId, nickname, url),
    );
    final url = await server.start();
    if (!mounted) return;
    if (url != null) {
      setState(() {
        _pairingServer = server;
        _pairingUrl = url;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _cancelPairingFocus.requestFocus(),
      );
    } else {
      setState(() {
        _pairingError =
            "Couldn't find a Wi-Fi address — is the TV connected to a network?";
        _editingRelayId = null;
      });
    }
  }

  Future<void> _onPairingSubmitted(
    String? editingId,
    String nickname,
    String url,
  ) async {
    if (!mounted) return;
    _pairingServer?.stop();
    setState(() {
      _pairingServer = null;
      _pairingUrl = null;
      _editingRelayId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _addRelayFocus.requestFocus(),
    );

    setState(() {
      _testingRelayName = nickname;
      _testStatus = RelayStatus.silent;
    });
    _silentTimer?.cancel();
    _silentTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _testStatus == RelayStatus.silent)
        setState(() => _testStatus = RelayStatus.waking);
    });

    final reachable = await _relayDirectoryApi.testReachableTolerant(url);
    _silentTimer?.cancel();
    if (!mounted) return;

    final updatedRelays = editingId != null
        ? _settings.relays
              .map(
                (r) => r.id == editingId
                    ? RelayEntry(
                        id: r.id,
                        nickname: nickname,
                        url: url,
                        isDefault: r.isDefault,
                      )
                    : r,
              )
              .toList()
        : [
            ..._settings.relays,
            RelayEntry(
              id: _uuid.v4(),
              nickname: nickname,
              url: url,
              isDefault: _settings.relays.isEmpty,
            ),
          ];
    await _persistRelays(updatedRelays);
    if (!mounted) return;

    final statusId = editingId ?? updatedRelays.last.id;
    final count = reachable
        ? (await _relayDirectoryApi.listRooms(url)).length
        : 0;
    if (!mounted) return;
    setState(() {
      _relayStatuses = {
        ..._relayStatuses,
        statusId: RelayReachability(reachable, count),
      };
      _testingRelayName = null;
    });
  }

  Future<void> _selectTheme(ThemeId id) async {
    // Screen 22 — no Save button here; a pick is applied and persisted the
    // moment it's made (the mockup's own "takes effect at once" copy).
    setState(() => _settings = _settings.copyWith(themeId: id));
    final store = ref.read(settingsStoreProvider);
    final persisted = await store.observe().first;
    await store.save(persisted.copyWith(themeId: id));
  }

  Future<void> _selectUiScale(double scale) async {
    // Same "applies at once" behavior as the theme picker above.
    setState(() => _settings = _settings.copyWith(uiScale: scale));
    final store = ref.read(settingsStoreProvider);
    final persisted = await store.observe().first;
    await store.save(persisted.copyWith(uiScale: scale));
  }

  void _cancelPairing() {
    _pairingServer?.stop();
    setState(() {
      _pairingServer = null;
      _pairingUrl = null;
      _editingRelayId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _addRelayFocus.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const LoadingScreen();
    }

    if (_showingRelaySettings) {
      return RelaySettingsPane(
        settings: _settings,
        relayStatuses: _relayStatuses,
        editingRelayId: _editingRelayId,
        pairingUrl: _pairingUrl,
        pairingError: _pairingError,
        testingRelayName: _testingRelayName,
        testStatus: _testStatus,
        addRelayFocus: _addRelayFocus,
        cancelPairingFocus: _cancelPairingFocus,
        backFocus: _relaySettingsBackFocus,
        onBack: () {
          setState(() => _showingRelaySettings = false);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _relaySettingsEntryFocus.requestFocus(),
          );
        },
        onMakeDefault: (entry) => _persistRelays(
          _settings.relays
              .map((r) => r.copyWith(isDefault: r.id == entry.id))
              .toList(),
        ),
        onEdit: (entry) => _startPairing(
          editingId: entry.id,
          prefillNickname: entry.nickname,
          prefillUrl: entry.url,
        ),
        onRemove: (entry) {
          final remaining = _settings.relays
              .where((r) => r.id != entry.id)
              .toList();
          final normalized = entry.isDefault && remaining.isNotEmpty
              ? [
                  for (var i = 0; i < remaining.length; i++)
                    remaining[i].copyWith(isDefault: i == 0),
                ]
              : remaining;
          _persistRelays(normalized);
        },
        onAddRelay: () => _startPairing(),
        onCancelPairing: _cancelPairing,
      );
    }

    return BackHandler(
      onBack: _leave,
      child: ColoredBox(
        color: AppColors.background,
        child: Stack(
          children: [
            ExcludeFocus(
              excluding: _maxSeatsMenuExpanded || _showingAddProfile,
              child: Padding(
                // Screen 08: 64 du from the top, 48 from the rail, 80 from
                // the right; a 380 du group column 56 du from the pane.
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.safeX.du(context),
                  64.du(context),
                  80.du(context),
                  AppSpacing.safeY.du(context),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 380.du(context),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _groupsKey,
                        child: _buildGroups(),
                      ),
                    ),
                    SizedBox(width: 56.du(context)),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _paneKey,
                        child: Focus(focusNode: _paneNode, child: _buildPane()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_maxSeatsMenuExpanded) ...[
              Positioned.fill(child: ColoredBox(color: AppScrims.dialog)),
              Center(
                child: MaxSeatsMenu(
                  selected: _settings.maxHostSeats,
                  onSelect: (value) {
                    _update((s) => s.copyWith(maxHostSeats: value));
                    setState(() => _maxSeatsMenuExpanded = false);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _maxHostSeatsFocus.requestFocus(),
                    );
                  },
                ),
              ),
            ],
            if (_showingAddProfile)
              AddProfileDialog(
                onCreate: _addProfile,
                onCancel: () => setState(() => _showingAddProfile = false),
              ),
          ],
        ),
      ),
    );
  }

  void _leave() {
    if (_maxSeatsMenuExpanded) {
      setState(() => _maxSeatsMenuExpanded = false);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maxHostSeatsFocus.requestFocus(),
      );
      return;
    }
    if (_serversChanged) {
      widget.onServersChanged();
    } else {
      widget.onBack();
    }
  }

  /// Applies a change on screen and persists it at once, merged over what
  /// is stored (so this screen never overwrites a field something else
  /// changed meanwhile).
  Future<void> _update(AppSettings Function(AppSettings) change) async {
    setState(() => _settings = change(_settings));
    final store = ref.read(settingsStoreProvider);
    final persisted = await store.observe().first;
    await store.save(change(persisted));
  }

  final _paneNode = FocusNode(
    debugLabel: 'settings-pane',
    canRequestFocus: false,
    skipTraversal: true,
  );

  KeyEventResult _groupsKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _enterPane();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Crossing into the pane lands somewhere deliberate — the current theme
  /// on Appearance, the pane's first row everywhere else — rather than on
  /// whichever row happens to sit level with the group you were on.
  void _enterPane() {
    if (_group == _Group.appearance && _appearanceEntryFocus.context != null) {
      _appearanceEntryFocus.requestFocus();
      return;
    }
    final nodes =
        _paneNode.traversalDescendants
            .where(
              (n) => n.canRequestFocus && !n.skipTraversal && n.context != null,
            )
            .toList()
          ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    if (nodes.isNotEmpty) nodes.first.requestFocus();
  }

  // Left out of the pane returns to the group that owns it, not whichever
  // group row happens to be geometrically nearest.
  KeyEventResult _paneKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _groupFocus[_group]!.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildGroups() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText('Settings', style: AppTypography.title1),
        SizedBox(height: 22.du(context)),
        // Scrolls when eight groups don't fit (a large UI size); the
        // version line rides at the end of the list rather than being
        // pinned under it.
        Expanded(
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, g) in _Group.values.indexed) ...[
                  if (i > 0) SizedBox(height: AppSpacing.sm.du(context)),
                  _GroupRow(
                    group: g,
                    selected: g == _group,
                    focusNode: _groupFocus[g]!,
                    onFocused: () => setState(() => _group = g),
                    onClick: _enterPane,
                  ),
                ],
                SizedBox(height: AppSpacing.xxl.du(context)),
                AppText(
                  [
                    'Reelay ${widget.versionName ?? ''}'.trim(),
                    'Android TV',
                  ].join('\n'),
                  style: AppTypography.caption.copyWith(height: 1.6),
                  color: AppColors.ink4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPane() {
    final rows = switch (_group) {
      _Group.watchTogether => _watchTogetherRows(),
      _Group.playback => _playbackRows(),
      _Group.subtitles => _subtitleRows(),
      _Group.servers => _serverRows(),
      _Group.appearance => _appearanceRows(),
      _Group.display => _displayRows(),
      _Group.profiles => _profileRows(),
      _Group.about => _aboutRows(),
    };
    return SingleChildScrollView(
      key: ValueKey(_group),
      controller: _scrollController,
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AppText(
                _group == _Group.appearance ? 'Theme' : _group.label,
                style: AppTypography.title2,
              ),
              if (_group == _Group.appearance) ...[
                const Spacer(),
                AppText(
                  'Applies to every screen · takes effect at once',
                  style: AppTypography.caption,
                ),
              ],
            ],
          ),
          SizedBox(height: (AppSpacing.sm + 14).du(context)),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) SizedBox(height: 14.du(context)),
            row,
          ],
        ],
      ),
    );
  }

  List<Widget> _watchTogetherRows() {
    final relay = _settings.defaultRelay;
    final status = relay == null ? null : _relayStatuses[relay.id];
    final (statusColor, statusLabel) = switch ((relay, status)) {
      (null, _) => (AppColors.ink4, 'Not set up'),
      (_, null) => (AppColors.ink4, 'Checking…'),
      (_, final s?) when s.reachable => (AppColors.success, 'Connected'),
      _ => (AppColors.error, 'Unreachable'),
    };
    return [
      if (widget.hint != null)
        AppText(
          widget.hint!,
          style: AppTypography.caption,
          color: AppColors.accent300,
        ),
      _SettingRow(
        label: 'Relay server',
        description: relay != null
            ? '${relay.nickname} · ${Uri.tryParse(relay.url)?.host ?? relay.url}'
            : 'Add one to host or join rooms',
        focusNode: _relaySettingsEntryFocus,
        onClick: () {
          setState(() => _showingRelaySettings = true);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _relaySettingsBackFocus.requestFocus(),
          );
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9.du(context),
              height: 9.du(context),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            SizedBox(width: 10.du(context)),
            AppText(
              statusLabel,
              style: AppTypography.caption,
              color: statusColor == AppColors.ink4
                  ? AppColors.ink3
                  : statusColor,
            ),
          ],
        ),
      ),
      _SettingRow(
        label: 'Maximum seats',
        description: 'People who can join a room you host',
        value: '${_settings.maxHostSeats}',
        focusNode: _maxHostSeatsFocus,
        onClick: () => setState(() => _maxSeatsMenuExpanded = true),
      ),
      _SettingRow(
        label: 'Show phone chat during playback',
        description: 'Messages from guests appear over the picture',
        toggle: _settings.showChatOverlay,
        onClick: () =>
            _update((s) => s.copyWith(showChatOverlay: !s.showChatOverlay)),
      ),
      _SettingRow(
        label: 'Chat overlay corner',
        description: 'Where phone messages appear during playback',
        value: _cornerLabel(_settings.chatOverlayCorner),
        onClick: () => _update((s) {
          const order = ChatOverlayCorner.values;
          return s.copyWith(
            chatOverlayCorner:
                order[(s.chatOverlayCorner.index + 1) % order.length],
          );
        }),
      ),
    ];
  }

  String _cornerLabel(ChatOverlayCorner c) => switch (c) {
    ChatOverlayCorner.topStart => 'Top left',
    ChatOverlayCorner.topEnd => 'Top right',
    ChatOverlayCorner.bottomStart => 'Bottom left',
    ChatOverlayCorner.bottomEnd => 'Bottom right',
  };

  List<Widget> _playbackRows() {
    const presets = AppSettings.bitratePresets;
    final current = presets
        .where((p) => p.kbps == _settings.maxVideoBitrateKbps)
        .firstOrNull;
    return [
      _SettingRow(
        label: 'Maximum transcode bitrate',
        description: 'Only used when a file can’t direct play',
        value: current?.label ?? '${_settings.maxVideoBitrateKbps} kbps',
        onClick: () => _update((s) {
          final i = presets.indexWhere((p) => p.kbps == s.maxVideoBitrateKbps);
          return s.copyWith(
            maxVideoBitrateKbps: presets[(i + 1) % presets.length].kbps,
          );
        }),
      ),
    ];
  }

  List<Widget> _subtitleRows() => [
    _SettingRow(
      label: 'Always burn in subtitles',
      description: 'Draw them into the picture even when the TV could render them itself',
      toggle: _settings.forceBurnSubtitles,
      onClick: () =>
          _update((s) => s.copyWith(forceBurnSubtitles: !s.forceBurnSubtitles)),
    ),
  ];

  List<Widget> _serverRows() {
    if (!_sourcesLoaded)
      return [AppText('Looking for servers…', style: AppTypography.body)];
    if (_sourcesError != null) {
      return [
        AppText(
          'Couldn’t reach plex.tv to list your servers. Everything already connected still works.',
          style: AppTypography.body,
        ),
      ];
    }
    if (_sources.isEmpty)
      return [
        AppText('No servers on this account.', style: AppTypography.body),
      ];
    return [
      AppText(
        'Every reachable server feeds the hub at once — turn one off to leave it out.',
        style: AppTypography.caption,
      ),
      for (final (index, source) in _sources.indexed)
        _SettingRow(
          label: source.name,
          description: 'Plex · ${source.owned ? 'Owned' : 'Shared with you'}',
          focusNode: index == 0 ? _firstSourceFocus : null,
          toggle: !_settings.disabledServerIds.contains(
            source.machineIdentifier,
          ),
          onClick: () {
            _serversChanged = true;
            _update((s) {
              final disabled = {...s.disabledServerIds};
              if (!disabled.remove(source.machineIdentifier))
                disabled.add(source.machineIdentifier);
              return s.copyWith(disabledServerIds: disabled);
            });
          },
        ),
    ];
  }

  List<Widget> _appearanceRows() => [
    ThemeList(
      current: _settings.themeId,
      onSelect: _selectTheme,
      currentFocus: _appearanceEntryFocus,
    ),
  ];

  List<Widget> _displayRows() => [
    _SettingRow(
      label: 'UI size',
      description: 'Scales the whole interface. Turn it up if things look small from where you sit — a TV can’t report its own screen size.',
      trailing: UiScaleStepper(
        value: _settings.uiScale,
        onChanged: _selectUiScale,
      ),
    ),
  ];

  List<Widget> _profileRows() => [
    for (final profile in _settings.profiles)
      _SettingRow(
        label: profile.name,
        description:
            'Plex · ${profile.plexUsername} · “${profile.watchTogetherName}” in rooms',
      ),
    _SettingRow(
      label: 'Add a profile',
      description: 'Sign in as someone else in the house',
      onClick: () => setState(() => _showingAddProfile = true),
    ),
  ];

  List<Widget> _aboutRows() => [
    _SettingRow(label: 'Version', value: widget.versionName ?? '—'),
  ];
  Future<void> _addProfile({
    required String name,
    required String watchTogetherName,
    required String token,
  }) async {
    await ref
        .read(appRootControllerProvider)
        .addProfile(
          name: name,
          watchTogetherName: watchTogetherName,
          token: token,
        );
    final settings = await ref.read(settingsStoreProvider).observe().first;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _showingAddProfile = false;
    });
  }
}

enum _Group {
  watchTogether('Watch Together', PhosphorIconsRegular.usersThree),
  playback('Playback', PhosphorIconsRegular.playCircle),
  subtitles('Subtitles', PhosphorIconsRegular.closedCaptioning),
  servers('Servers', PhosphorIconsRegular.hardDrives),
  appearance('Appearance', PhosphorIconsRegular.palette),
  display('Display', PhosphorIconsRegular.monitor),
  profiles('Profiles', PhosphorIconsRegular.user),
  about('About', PhosphorIconsRegular.info);

  final String label;
  final IconData icon;
  const _Group(this.label, this.icon);
}

RoundedRectangleBorder _rowShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );

SurfaceColors get _groupColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink3,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surface,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _groupBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.transparent),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// A group in the left column: 72 du, icon and name; the selected group
/// keeps a surface fill and ink spine while focus is in the pane.
class _GroupRow extends StatelessWidget {
  final _Group group;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onFocused;
  final VoidCallback onClick;

  const _GroupRow({
    required this.group,
    required this.selected,
    required this.focusNode,
    required this.onFocused,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 72.du(context)),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        onFocusChange: (f) {
          if (f) onFocused();
        },
        shape: _rowShape(context),
        colors: _groupColors,
        border: _groupBorder,
        contentAlignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.du(context)),
          child: Row(
            children: [
              AppIcon(group.icon, size: 24),
              SizedBox(width: AppSpacing.lg.du(context)),
              AppText(group.label, style: AppTypography.body, color: null),
            ],
          ),
        ),
      ),
    );
  }
}

SurfaceColors get _settingColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _settingBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// One setting (screen 08): 96 du minimum, label and a line saying what it
/// does, and its current value stated at the trailing edge — a value, a
/// switch, or a status. With no [onClick] it's a plain, unfocusable fact.
class _SettingRow extends StatefulWidget {
  final String label;
  final String? description;
  final String? value;
  final bool? toggle;
  final Widget? trailing;
  final FocusNode? focusNode;
  final VoidCallback? onClick;

  const _SettingRow({
    required this.label,
    this.description,
    this.value,
    this.toggle,
    this.trailing,
    this.focusNode,
    this.onClick,
  });

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final trailing =
        widget.trailing ??
        (widget.toggle != null
            ? _ToggleIndicator(enabled: widget.toggle!)
            : widget.value != null
            ? AppText(
                widget.value!,
                style: AppTypography.label,
                color: _focused ? AppColors.ink : AppColors.ink2,
              )
            : null);
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xl.du(context),
        vertical: AppSpacing.lg.du(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  widget.label,
                  style: AppTypography.body.copyWith(
                    height: 1.3,
                    fontWeight: _focused ? FontWeight.w500 : FontWeight.w400,
                  ),
                  color: _focused ? AppColors.ink : AppColors.ink2,
                ),
                if (widget.description != null) ...[
                  SizedBox(height: 3.du(context)),
                  AppText(
                    widget.description!,
                    style: AppTypography.caption,
                    color: _focused ? AppColors.ink2 : AppColors.ink3,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 20.du(context)), trailing],
        ],
      ),
    );
    final onClick = widget.onClick;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 96.du(context)),
      child: onClick == null
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: AppColors.surface,
                shape: _rowShape(context).copyWith(
                  side: BorderSide(
                    color: AppColors.line,
                    width: AppShape.borderWidth.du(context),
                  ),
                ),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: content,
              ),
            )
          : FocusableSurface(
              onClick: onClick,
              focusNode: widget.focusNode,
              onFocusChange: (f) => setState(() => _focused = f),
              shape: _rowShape(context),
              colors: _settingColors,
              border: _settingBorder,
              contentAlignment: AlignmentDirectional.centerStart,
              child: content,
            ),
    );
  }
}

/// Screen 08's switch, drawn: 72x40 track, 28 du thumb. Decorative — the
/// row is the focus target and Select flips it.
class _ToggleIndicator extends StatelessWidget {
  final bool enabled;

  const _ToggleIndicator({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final inset = 4.du(context);
    return Container(
      width: 72.du(context),
      height: 40.du(context),
      padding: EdgeInsets.all(inset),
      alignment: enabled
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: enabled ? AppColors.accent700 : AppColors.canvas,
        border: Border.all(
          color: AppColors.lineStrong,
          width: AppShape.borderWidth.du(context),
        ),
        borderRadius: BorderRadius.circular(20.du(context)),
      ),
      child: Container(
        width: 28.du(context),
        height: 28.du(context),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppColors.ink : AppColors.ink4,
        ),
      ),
    );
  }
}
