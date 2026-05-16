import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'services/app_log_service.dart';
import 'services/app_lifecycle_manager.dart';
import 'pages/browser_page.dart';
import 'pages/clipboard_page.dart';
import 'pages/game_2048_page.dart';
import 'pages/calculator_page.dart';
import 'pages/downloads_page.dart';
import 'pages/data_management_page.dart';
import 'pages/settings_page.dart';
import 'pages/easytier_settings_page.dart';
import 'pages/remote_control_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appLogService = AppLogService.instance;
  await appLogService.initialize();

  // 初始化应用生命周期管理器，确保服务默认关闭状态
  await AppLifecycleManager().initialize();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(appLogService.logFlutterError(details));
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
    unawaited(appLogService.logUnhandledError(error, stackTrace));
    return true;
  };

  await runZonedGuarded(
    () async {
      await appLogService.log('Application bootstrap start');
      runApp(const MyApp());
    },
    (Object error, StackTrace stackTrace) {
      unawaited(appLogService.logUnhandledError(error, stackTrace));
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.browserWebViewEnabled = true});

  final bool browserWebViewEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '若轻',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (context) => BrowserPage(enableWebView: browserWebViewEnabled),
        '/game-2048': (context) => const Game2048Page(),
        '/calculator': (context) => const CalculatorPage(),
        '/clipboard': (context) => const ClipboardPage(),
        '/downloads': (context) => const DownloadsPage(),
        '/data-management': (context) => const DataManagementPage(),
        '/settings': (context) => const SettingsPage(),
        '/easytier': (context) => const EasyTierSettingsPage(),
        '/remote-control': (context) => const RemoteControlPage(),
      },
    );
  }
}
