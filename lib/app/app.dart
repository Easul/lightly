import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/app_toast.dart';
import 'routes.dart';

/// Root application widget.
///
/// Extracted from `main.dart` so that file is bootstrap-only. Behavior is
/// identical to the previous inline `MyApp`: same title, theme, navigator key,
/// initial route, and route table.
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.browserWebViewEnabled = true});

  final bool browserWebViewEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppToast.navigatorKey,
      title: '若轻',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: buildAppRoutes(browserWebViewEnabled: browserWebViewEnabled),
    );
  }
}
