import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/plex/plex_auth_api.dart';
import '../../kit/text.dart';
import '../../state/data_providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _pollInterval = Duration(milliseconds: 2000);

sealed class _AuthUiState {
  const _AuthUiState();
}

class _Loading extends _AuthUiState {
  const _Loading();
}

class _AwaitingLink extends _AuthUiState {
  final String code;
  const _AwaitingLink(this.code);
}

class _AuthError extends _AuthUiState {
  final String message;
  const _AuthError(this.message);
}

/// Ports ui/auth/AuthScreen.kt — Plex PIN-based device linking: create a
/// PIN, show the code, poll until the user approves it on plex.tv/link (or
/// the PIN's own expiresIn deadline passes — no auto-retry on expiry,
/// matching the Kotlin source exactly).
class AuthScreen extends ConsumerStatefulWidget {
  final ValueChanged<String> onLoggedIn;

  const AuthScreen({super.key, required this.onLoggedIn});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  _AuthUiState _state = const _Loading();
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
        setState(() => _state = const _AuthError('Code expired — restart the app to get a new one'));
        return;
      }

      await ref.read(secureTokenStoreProvider).saveToken(authToken);
      if (_disposed) return;
      widget.onLoggedIn(authToken);
    } catch (e) {
      if (_disposed) return;
      setState(() => _state = _AuthError('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(child: _buildState(_state)),
      ),
    );
  }

  Widget _buildState(_AuthUiState state) {
    return switch (state) {
      _Loading() => const AppText('Connecting to Plex…'),
      _AwaitingLink(:final code) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 220,
              height: 220,
              color: AppColors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(data: 'https://www.plex.tv/link/', backgroundColor: AppColors.white),
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
                    AppText(code, style: AppTypography.displayMedium),
                  ],
                ),
              ),
            ),
          ],
        ),
      _AuthError(:final message) => AppText('Error: $message'),
    };
  }
}
