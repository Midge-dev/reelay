import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/app_root.dart';

void main() {
  runApp(const ProviderScope(child: ReelayApp()));
}

class ReelayApp extends StatelessWidget {
  const ReelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Reelay',
      color: const Color(0xFFAD2BD7),
      home: const AppRoot(),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
        );
      },
    );
  }
}
