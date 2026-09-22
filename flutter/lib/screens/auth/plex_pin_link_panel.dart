import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/plex/plex_auth_api.dart';
import '../../kit/text.dart';
import '../../state/data_providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _pollInterval = Duration(milliseconds: 2000);

sealed class _LinkUiState {
  const _LinkUiState();
}

class _Loading extends _LinkUiState {
  const _Loading();
}

class _AwaitingLink extends _LinkUiState {
  final String code;
  const _AwaitingLink(this.code);
}

class _LinkError extends _LinkUiState {
  final String message;
  const _LinkError(this.message);
}

/// The actual Plex PIN-linking UI + polling loop, factored out of
/// AuthScreen so screen 07b's add-profile dialog can embed the same "sign
/// in with Plex" step inline rather than duplicating it. Does not persist
/// the resulting token anywhere itself — callers decide where it belongs
/// (the legacy single key for first-run login, or a specific profile's
/// keyed token when adding a profile), via [onLinked].
class PlexPinLinkPanel extends ConsumerStatefulWidget {
  final ValueChanged<String> onLinked;

  const PlexPinLinkPanel({super.key, required this.onLinked});

  @override
  ConsumerState<PlexPinLinkPanel> createState() => _PlexPinLinkPanelState();
}

class _PlexPinLinkPanelState extends ConsumerState<PlexPinLinkPanel> {
  _LinkUiState _state = const _Loading();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final clientIdentifier = await ref.read(plexIdentityProvider).getOrCreateClientIdentifier();
      final api = PlexAuthApi(clientIdentifier);

      final pin = await api.createPin();
      if (_disposed) return;
      setState(() => _state = _AwaitingLink(pin.code));

      final deadline = DateTime.now().add(Duration(seconds: pin.expiresIn));
      String? authToken;
      while (authToken == null && DateTime.now().isBefore(deadline)) {
        await Future.delayed(_pollInterval);
        if (_disposed) return;
        authToken = (await api.pollPin(pin.id)).authToken;
      }
      if (_disposed) return;

      if (authToken == null) {
        setState(() => _state = const _LinkError('Code expired — restart to get a new one'));
        return;
      }

      widget.onLinked(authToken);
    } catch (e) {
      if (_disposed) return;
      setState(() => _state = _LinkError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) => _buildState(_state);

  Widget _buildState(_LinkUiState state) {
    return switch (state) {
      _Loading() => const AppText('Connecting to Plex…'),
      _AwaitingLink(:final code) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 220,
              height: 220,
              color: AppColors.inkOnArt,
              padding: const EdgeInsets.all(16),
              child: QrImageView(data: 'https://www.plex.tv/link/', backgroundColor: AppColors.inkOnArt),
            ),
            const SizedBox(width: 48),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const AppText(
                      'Scan with your phone, or on any device visit plex.tv/link, then enter:',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    AppText(code, style: AppTypography.title2),
                  ],
                ),
              ),
            ),
          ],
        ),
      _LinkError(:final message) => AppText('Error: $message'),
    };
  }
}
