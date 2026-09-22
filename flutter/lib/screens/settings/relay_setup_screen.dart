import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/text.dart';
import '../../pairing/pairing_server.dart';
import '../../state/data_providers.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/click_to_type_text_field.dart';
import '../common/neon_scrollbar.dart';

const _uuid = Uuid();

/// Ports ui/settings/RelaySetupScreen.kt — the first-run watch-together
/// setup: paste a relay URL directly, or pair it in from a phone via the
/// local PairingServer. Explicit focusProperties up/down wiring from the
/// Kotlin source is intentionally not ported 1:1 — this is a simple
/// top-to-bottom form and Flutter's default directional focus traversal
/// already handles that shape correctly (confirmed during the
/// flutter-reelay PoC); only state-transition focus restores (e.g. after
/// pairing completes) need explicit requestFocus() calls, kept below.
class RelaySetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;

  const RelaySetupScreen({super.key, required this.onDone});

  @override
  ConsumerState<RelaySetupScreen> createState() => _RelaySetupScreenState();
}

class _RelaySetupScreenState extends ConsumerState<RelaySetupScreen> {
  String _relayUrl = '';
  String _relayNickname = 'My relay';

  PairingServer? _pairingServer;
  String? _pairingUrl;
  String? _pairingError;

  final _relayUrlFocus = FocusNode(debugLabel: 'relay-url');
  final _pairButtonFocus = FocusNode(debugLabel: 'pair-button');
  final _cancelPairingFocus = FocusNode(debugLabel: 'cancel-pairing');
  final _saveFocus = FocusNode(debugLabel: 'save');
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _pairingServer?.stop();
    _relayUrlFocus.dispose();
    _pairButtonFocus.dispose();
    _cancelPairingFocus.dispose();
    _saveFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final store = ref.read(settingsStoreProvider);
    final current = await store.observe().first;
    final url = _relayUrl.trim();
    final relays = url.isEmpty
        ? const <RelayEntry>[]
        : [
            RelayEntry(
              id: _uuid.v4(),
              nickname: _relayNickname.trim().isEmpty
                  ? 'My relay'
                  : _relayNickname.trim(),
              url: url,
              isDefault: true,
            ),
          ];
    await store.save(current.copyWith(relays: relays));
    if (!mounted) return;
    widget.onDone();
  }

  Future<void> _startPairing() async {
    setState(() => _pairingError = null);
    final server = PairingServer(
      onSubmitted: (nickname, url) {
        if (!mounted) return;
        setState(() {
          _relayNickname = nickname;
          _relayUrl = url;
          _pairingServer?.stop();
          _pairingServer = null;
          _pairingUrl = null;
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _saveFocus.requestFocus(),
        );
      },
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
      setState(
        () => _pairingError =
            "Couldn't find a Wi-Fi address — is the TV connected to a network?",
      );
    }
  }

  void _cancelPairing() {
    _pairingServer?.stop();
    setState(() {
      _pairingServer = null;
      _pairingUrl = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _pairButtonFocus.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.all(48.du(context)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 640.du(context)),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AppText(
                          'Set up watch-together',
                          style: AppTypography.title2,
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: 8.du(context), bottom: 32.du(context)),
                          child: const AppText(
                            "Reelay syncs playback with whoever you're watching with, over a "
                            'relay server. Paste its URL below, or scan the QR from your phone.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 500.du(context),
                          child: ClickToTypeTextField(
                            value: _relayUrl,
                            onValueChange: (v) => setState(() => _relayUrl = v),
                            focusNode: _relayUrlFocus,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(top: 16.du(context)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppButton(
                                onClick: _startPairing,
                                focusNode: _pairButtonFocus,
                                child: const AppText('Pair from phone'),
                              ),
                            ],
                          ),
                        ),
                        if (_pairingError != null)
                          Padding(
                            padding: EdgeInsets.only(top: 16.du(context)),
                            child: AppText(_pairingError!),
                          ),
                        if (_pairingUrl != null)
                          Container(
                            margin: EdgeInsets.only(top: 24.du(context)),
                            padding: EdgeInsets.all(24.du(context)),
                            color: AppColors.surface,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 160.du(context),
                                  height: 160.du(context),
                                  color: AppColors.inkOnArt,
                                  padding: EdgeInsets.all(12.du(context)),
                                  child: QrImageView(
                                    data: _pairingUrl!,
                                    backgroundColor: AppColors.inkOnArt,
                                  ),
                                ),
                                SizedBox(width: 24.du(context)),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const AppText(
                                        'Scan with your phone (same Wi-Fi as the TV), or visit:',
                                      ),
                                      SizedBox(height: 12.du(context)),
                                      AppText(
                                        _pairingUrl!,
                                        style: AppTypography.body,
                                      ),
                                      SizedBox(height: 12.du(context)),
                                      const AppText(
                                        "Paste the relay URL there and it'll appear here automatically.",
                                      ),
                                      SizedBox(height: 12.du(context)),
                                      AppOutlinedButton(
                                        onClick: _cancelPairing,
                                        focusNode: _cancelPairingFocus,
                                        child: const AppText('Cancel'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.only(top: 32.du(context)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppButton(
                                onClick: _relayUrl.trim().isNotEmpty
                                    ? _saveAndContinue
                                    : () {},
                                enabled: _relayUrl.trim().isNotEmpty,
                                focusNode: _saveFocus,
                                child: const AppText('Save & continue'),
                              ),
                              SizedBox(width: 24.du(context)),
                              AppOutlinedButton(
                                onClick: widget.onDone,
                                child: const AppText('Skip for now'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 12.du(context)),
              child: NeonScrollbar(controller: _scrollController),
            ),
          ],
        ),
      ),
    );
  }
}
