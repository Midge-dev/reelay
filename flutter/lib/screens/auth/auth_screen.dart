import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data_providers.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import 'plex_pin_link_panel.dart';

/// Ports ui/auth/AuthScreen.kt — Plex PIN-based device linking, full-screen
/// (the pre-profiles/no-token-yet case). The actual linking UI and polling
/// loop live in [PlexPinLinkPanel], shared with screen 07b's embedded
/// "sign in with Plex" step.
class AuthScreen extends ConsumerWidget {
  final ValueChanged<String> onLoggedIn;

  const AuthScreen({super.key, required this.onLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.all(48.du(context)),
        child: Center(
          child: PlexPinLinkPanel(
            onLinked: (token) async {
              await ref.read(secureTokenStoreProvider).saveToken(token);
              onLoggedIn(token);
            },
          ),
        ),
      ),
    );
  }
}
