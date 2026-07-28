import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tdlib/tdlib.dart';

import 'features/telegram/telegram_host_gateway.dart';
import 'features/telegram/telegram_tdlib_service.dart';
import 'pages/telegram_checkin_page.dart';
import 'services/app_toast.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await TdPlugin.initialize('libtdjson.so');
  }
  final hostGateway = TelegramHostGateway.instance;
  await hostGateway.initialize();
  final telegram = TelegramTdlibService.instance;
  telegram.proxyPort = hostGateway.context.value.proxyPort;
  hostGateway.context.addListener(() {
    telegram.proxyPort = hostGateway.context.value.proxyPort;
  });
  runApp(const TelegramPluginApp());
}

class TelegramPluginApp extends StatelessWidget {
  const TelegramPluginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppToast.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Lightly TG 插件',
      theme: AppTheme.light(),
      home: const TelegramCheckinPage(),
    );
  }
}
