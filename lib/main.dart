import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'features/ai/ai_history_database.dart';
import 'features/telegram/telegram_tdlib_service.dart';

// Re-export so existing `package:lightly/main.dart` importers (e.g. tests)
// keep resolving `MyApp` after it moved to `lib/app/app.dart`.
export 'app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices.production();
  final appLogService = services.logService;
  await appLogService.initialize();

  // Inject the local-proxy port into Telegram so it depends only on the
  // LocalProxyEndpointProvider port, not on the proxy implementation.
  TelegramTdlibService.instance.proxyEndpointProvider =
      services.localProxyEndpoint;

  // Inject the shared database behind the AppDatabaseProvider port so AI history
  // does not depend on the concrete database class. Done before runApp, so
  // every page that reads AI history is constructed after the provider is wired.
  AiHistoryDatabase.instance.databaseProvider = services.appDatabase;

  // 初始化应用生命周期管理器，确保服务默认关闭状态
  await services.runtimeCoordinator.initializePersistedServices();
  await services.lifecycleManager.initialize();

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
