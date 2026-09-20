import 'package:flutter/widgets.dart';

/// Ports Compose's `BackHandler(onBack)` — intercepts the system back
/// button/gesture (Android TV remote's back/menu key) via PopScope, since
/// this app has no real Navigator route stack to pop (AppRoot switches on
/// AppState directly, same as MainActivity.kt's approach).
class BackHandler extends StatelessWidget {
  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  const BackHandler({super.key, this.enabled = true, required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && enabled) onBack();
      },
      child: child,
    );
  }
}
