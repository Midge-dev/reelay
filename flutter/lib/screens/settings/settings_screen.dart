import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart';
import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/filter_chip.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/list_item.dart';
import '../../kit/radio_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/switch.dart';
import '../../kit/text.dart';
import '../../pairing/pairing_server.dart';
import '../../state/data_providers.dart';
import '../../sync/relay_directory_api.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/loading_screen.dart';
import '../common/neon_scrollbar.dart';
import '../common/relay_status.dart';
import 'chat_corner_picker.dart';
import 'max_seats_menu.dart';
import 'relay_settings_pane.dart';

const _uuid = Uuid();

/// Ports ui/settings/SettingsScreen.kt. The Kotlin source's explicit
/// focusProperties up/down wiring across every row is not ported 1:1 —
/// same rationale as RelaySetupScreen: it's a vertically-stacked form and
/// Flutter's default directional traversal already gets this shape right
/// (proven in the flutter-reelay PoC). MaxSeatsMenu keeps its explicit
/// focus-trap (checklist #8) since that's a real hazard, not just wiring.
class SettingsScreen extends ConsumerStatefulWidget {
  final String accountToken;
  final String clientIdentifier;
  final String? hint;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const SettingsScreen({
    super.key,
    required this.accountToken,
    required this.clientIdentifier,
    this.hint,
    required this.onBack,
    required this.onSaved,
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

  PairingServer? _pairingServer;
  String? _pairingUrl;
  String? _pairingError;
  String? _editingRelayId;
  String? _testingRelayName;
  RelayStatus _testStatus = RelayStatus.silent;
  Timer? _silentTimer;

  final _relayDirectoryApi = RelayDirectoryApi();
  Map<String, RelayReachability?> _relayStatuses = {};

  final _relaySettingsEntryFocus = FocusNode(debugLabel: 'relay-settings-entry');
  final _maxHostSeatsFocus = FocusNode(debugLabel: 'max-host-seats');
  final _addRelayFocus = FocusNode(debugLabel: 'add-relay');
  final _cancelPairingFocus = FocusNode(debugLabel: 'cancel-pairing');
  final _saveFocus = FocusNode(debugLabel: 'save');
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSources();
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
      final sources = await PlexResourcesApi(widget.clientIdentifier).listServers(widget.accountToken);
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
      final count = reachable ? (await _relayDirectoryApi.listRooms(entry.url)).length : 0;
      if (!mounted) return;
      setState(() => _relayStatuses = {..._relayStatuses, entry.id: RelayReachability(reachable, count)});
    }
  }

  @override
  void dispose() {
    _pairingServer?.stop();
    _silentTimer?.cancel();
    _relaySettingsEntryFocus.dispose();
    _maxHostSeatsFocus.dispose();
    _addRelayFocus.dispose();
    _cancelPairingFocus.dispose();
    _saveFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _persistRelays(List<RelayEntry> newRelays) async {
    setState(() => _settings = _settings.copyWith(relays: newRelays));
    final store = ref.read(settingsStoreProvider);
    final persisted = await store.observe().first;
    await store.save(persisted.copyWith(relays: newRelays));
  }

  void _startPairing({String? editingId, String prefillNickname = '', String prefillUrl = ''}) async {
    setState(() {
      _pairingError = null;
      _editingRelayId = editingId;
    });
    final server = PairingServer(
      prefillNickname: prefillNickname,
      prefillUrl: prefillUrl,
      onSubmitted: (nickname, url) => _onPairingSubmitted(editingId, nickname, url),
    );
    final url = await server.start();
    if (!mounted) return;
    if (url != null) {
      setState(() {
        _pairingServer = server;
        _pairingUrl = url;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _cancelPairingFocus.requestFocus());
    } else {
      setState(() {
        _pairingError = "Couldn't find a Wi-Fi address — is the TV connected to a network?";
        _editingRelayId = null;
      });
    }
  }

  Future<void> _onPairingSubmitted(String? editingId, String nickname, String url) async {
    if (!mounted) return;
    _pairingServer?.stop();
    setState(() {
      _pairingServer = null;
      _pairingUrl = null;
      _editingRelayId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _addRelayFocus.requestFocus());

    setState(() {
      _testingRelayName = nickname;
      _testStatus = RelayStatus.silent;
    });
    _silentTimer?.cancel();
    _silentTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _testStatus == RelayStatus.silent) setState(() => _testStatus = RelayStatus.waking);
    });

    final reachable = await _relayDirectoryApi.testReachableTolerant(url);
    _silentTimer?.cancel();
    if (!mounted) return;

    final updatedRelays = editingId != null
        ? _settings.relays.map((r) => r.id == editingId ? RelayEntry(id: r.id, nickname: nickname, url: url, isDefault: r.isDefault) : r).toList()
        : [
            ..._settings.relays,
            RelayEntry(id: _uuid.v4(), nickname: nickname, url: url, isDefault: _settings.relays.isEmpty),
          ];
    await _persistRelays(updatedRelays);
    if (!mounted) return;

    final statusId = editingId ?? updatedRelays.last.id;
    final count = reachable ? (await _relayDirectoryApi.listRooms(url)).length : 0;
    if (!mounted) return;
    setState(() {
      _relayStatuses = {..._relayStatuses, statusId: RelayReachability(reachable, count)};
      _testingRelayName = null;
    });
  }

  void _cancelPairing() {
    _pairingServer?.stop();
    setState(() {
      _pairingServer = null;
      _pairingUrl = null;
      _editingRelayId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _addRelayFocus.requestFocus());
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
        onBack: () {
          setState(() => _showingRelaySettings = false);
          WidgetsBinding.instance.addPostFrameCallback((_) => _relaySettingsEntryFocus.requestFocus());
        },
        onMakeDefault: (entry) => _persistRelays(_settings.relays.map((r) => r.copyWith(isDefault: r.id == entry.id)).toList()),
        onEdit: (entry) => _startPairing(editingId: entry.id, prefillNickname: entry.nickname, prefillUrl: entry.url),
        onRemove: (entry) {
          final remaining = _settings.relays.where((r) => r.id != entry.id).toList();
          final normalized = entry.isDefault && remaining.isNotEmpty
              ? [for (var i = 0; i < remaining.length; i++) remaining[i].copyWith(isDefault: i == 0)]
              : remaining;
          _persistRelays(normalized);
        },
        onAddRelay: () => _startPairing(),
        onCancelPairing: _cancelPairing,
      );
    }

    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText('Settings', style: AppTypography.displaySmall),
                      const SizedBox(height: 32),
                      _SettingsGroup(
                        title: 'Libraries',
                        showRule: false,
                        child: _buildSourcesSection(),
                      ),
                      _SettingsGroup(
                        title: 'Watch Together',
                        showRule: true,
                        child: _buildWatchTogetherSection(),
                      ),
                      _SettingsGroup(
                        title: 'Playback',
                        showRule: true,
                        child: _buildPlaybackSection(),
                      ),
                      _SettingsGroup(
                        title: 'Chat',
                        showRule: true,
                        child: _buildChatSection(),
                      ),
                      const SizedBox(height: 32),
                      AppButton(
                        onClick: () async {
                          await ref.read(settingsStoreProvider).save(_settings);
                          if (mounted) widget.onSaved();
                        },
                        focusNode: _saveFocus,
                        child: const AppText('Save'),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
                child: NeonScrollbar(controller: _scrollController),
              ),
            ],
          ),
          if (_maxSeatsMenuExpanded) ...[
            Positioned.fill(child: ColoredBox(color: AppColors.scrim.withValues(alpha: 0.4))),
            Positioned(
              left: 220,
              top: 220,
              child: MaxSeatsMenu(
                selected: _settings.maxHostSeats,
                onSelect: (value) {
                  setState(() {
                    _settings = _settings.copyWith(maxHostSeats: value);
                    _maxSeatsMenuExpanded = false;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) => _maxHostSeatsFocus.requestFocus());
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourcesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText('Available sources'),
        const SizedBox(height: 8),
        if (!_sourcesLoaded)
          const AppText('Loading sources…')
        else if (_sourcesError != null)
          AppText("Couldn't load sources: $_sourcesError")
        else if (_sources.isEmpty)
          const AppText('No sources found')
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final source in _sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppListItem(
                    selected: _settings.selectedServerId == source.machineIdentifier,
                    onClick: () => setState(() => _settings = _settings.copyWith(selectedServerId: source.machineIdentifier)),
                    leading: AppRadioButton(selected: _settings.selectedServerId == source.machineIdentifier),
                    headline: AppText('${source.name}${source.owned ? ' (owned)' : ''}'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildWatchTogetherSection() {
    final defaultRelay = _settings.defaultRelay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.hint != null) ...[
          AppText(widget.hint!, color: AppColors.accent),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 64,
          child: FocusableSurface(
            onClick: () {
              setState(() => _showingRelaySettings = true);
            },
            focusNode: _relaySettingsEntryFocus,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
            colors: SurfaceColors(container: AppColors.background, content: AppColors.onSurfaceVariant, focusedContent: AppColors.white),
            border: const SurfaceBorder(idle: SurfaceBorderSide.solid(AppColors.dimBorder), focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient)),
            glow: const SurfaceGlow(focusedColor: AppColors.accentGlow),
            contentAlignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppText('Relay settings'),
                      AppText(
                        defaultRelay != null ? '${defaultRelay.nickname} · Default' : 'None configured',
                        color: AppColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const AppText('›', color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: FocusableSurface(
            onClick: () => setState(() => _maxSeatsMenuExpanded = true),
            focusNode: _maxHostSeatsFocus,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
            colors: SurfaceColors(container: AppColors.background, content: AppColors.onSurfaceVariant, focusedContent: AppColors.white),
            border: const SurfaceBorder(idle: SurfaceBorderSide.solid(AppColors.dimBorder), focused: SurfaceBorderSide.gradient(AppFocusTreatment.focusedGradient)),
            glow: const SurfaceGlow(focusedColor: AppColors.accentGlow),
            contentAlignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppText('Maximum seats'),
                  const Spacer(),
                  AppText('${_settings.maxHostSeats}', color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText('Max transcode video bitrate'),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final preset in AppSettings.bitratePresets) ...[
              Builder(builder: (context) {
                final selected = _settings.maxVideoBitrateKbps == preset.kbps;
                return AppFilterChip(
                  selected: selected,
                  onClick: () => setState(() => _settings = _settings.copyWith(maxVideoBitrateKbps: preset.kbps)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) const Padding(padding: EdgeInsets.only(right: 8), child: AppText('✓')),
                      AppText(preset.label),
                    ],
                  ),
                );
              }),
              const SizedBox(width: 16),
            ],
          ],
        ),
        const SizedBox(height: 24),
        const AppText('Force-burn subtitles into video even when not required'),
        const SizedBox(height: 8),
        AppSwitch(
          checked: _settings.forceBurnSubtitles,
          onCheckedChange: (v) => setState(() => _settings = _settings.copyWith(forceBurnSubtitles: v)),
        ),
      ],
    );
  }

  Widget _buildChatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText('Show watch-together chat messages on screen during playback'),
        const SizedBox(height: 8),
        AppSwitch(
          checked: _settings.showChatOverlay,
          onCheckedChange: (v) => setState(() => _settings = _settings.copyWith(showChatOverlay: v)),
        ),
        const SizedBox(height: 24),
        const AppText('Chat position'),
        const SizedBox(height: 4),
        const AppText('Pick the corner messages appear in', color: AppColors.onSurfaceVariant),
        const SizedBox(height: 14),
        ChatCornerPicker(
          selected: _settings.chatOverlayCorner,
          onSelect: (corner) => setState(() => _settings = _settings.copyWith(chatOverlayCorner: corner)),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final bool showRule;
  final Widget child;

  const _SettingsGroup({required this.title, required this.showRule, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRule) ...[
          const SizedBox(height: 26),
          Container(height: 1, color: AppColors.surfaceVariant),
          const SizedBox(height: 14),
        ],
        AppText(title.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w500), color: AppColors.onSurfaceVariant),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
