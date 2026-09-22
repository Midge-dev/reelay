import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/app_root.dart';
import 'theme/scale.dart';

void main() {
  runApp(const ProviderScope(child: ReelayApp()));
}

class ReelayApp extends StatelessWidget {
  const ReelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Reelay',
      color: const Color(0xFF9184D9),
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
      // Establishes the one scale factor (screenHeight / 1080) the whole
      // app multiplies design units by — DESIGN.md non-negotiable #5. Do
      // this here, once, rather than at any individual screen, or the
      // numbers get hard-coded at 1.0.
      builder: (context, child) => AppScale(
        factor: MediaQuery.sizeOf(context).height / 1080,
        child: child!,
      ),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
        );
      },
    );
  }
}
