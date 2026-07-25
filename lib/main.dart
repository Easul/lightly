import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tdlib/tdlib.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'telegram_checkin/telegram_tdlib_service.dart';

// Re-export so existing `package:lightly/main.dart` importers (e.g. tests)
// keep resolving `MyApp` after it moved to `lib/app/app.dart`.
export 'app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await TdPlugin.initialize('libtdjson.so');
  }
  final services = AppServices.production();
  final appLogService = services.logService;
  await appLogService.initialize();

  // Inject the local-proxy port into Telegram so it depends only on the
  // LocalProxyEndpointProvider port, not on the proxy implementation.
  TelegramTdlibService.instance.proxyEndpointProvider =
      services.localProxyEndpoint;

  // 初始化应用生命周期管理器，确保服务默认关闭状态
  await services.lifecycleManager.initialize();

  final simpleFileManagerService = services.simpleFileManager;
  final simpleFileManagerSettings = await simpleFileManagerService
      .loadSettings();
  if (simpleFileManagerSettings.enabled) {
    try {
      await simpleFileManagerService.start(settings: simpleFileManagerSettings);
    } catch (error, stackTrace) {
      unawaited(appLogService.logUnhandledError(error, stackTrace));
    }
  }

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
