import 'package:flutter/material.dart';

import '../pages/browser_page.dart';
import '../pages/clipboard_page.dart';
import '../pages/game_2048_page.dart';
import '../pages/calculator_page.dart';
import '../pages/downloads_page.dart';
import '../pages/data_management_page.dart';
import '../pages/about_version_page.dart';
import '../pages/settings_page.dart';
import '../pages/optional_plugin_settings_page.dart';
import '../pages/browser_history_page.dart';
import '../pages/easytier_settings_page.dart';
import '../features/remote_control/presentation/pages/remote_control_page.dart';
import '../pages/simple_file_manager_settings_page.dart';
import '../pages/telegram_checkin_page.dart';
import '../pages/tools_page.dart';
import '../pages/life_runtime_page.dart';
import '../pages/translation_tool_page.dart';
import '../pages/ai_chat_page.dart';
import '../features/music/presentation/music_player_page.dart';
import '../features/remote_control/infrastructure/remote_control_platform_gateway.dart';
import '../features/remote_control/infrastructure/remote_control_service.dart';
import '../features/optional_plugins/domain/optional_feature.dart';
import '../features/optional_plugins/presentation/optional_feature_gate.dart';
import '../services/app_log_service.dart';
import '../services/app_toast.dart';
import 'remote_control_page_coordinator.dart';

/// Application route table.
///
/// Kept behaviorally identical to the previous inline `MyApp.routes` map;
/// extracted only so `main.dart` is bootstrap-only and routing has a single
/// discoverable owner. Do not change route names or destinations here without
/// treating it as a navigation behavior change.
Map<String, WidgetBuilder> buildAppRoutes({bool browserWebViewEnabled = true}) {
  return {
    '/': (context) => BrowserPage(enableWebView: browserWebViewEnabled),
    '/game-2048': (context) => const Game2048Page(),
    '/calculator': (context) => const CalculatorPage(),
    '/clipboard': (context) => const ClipboardPage(),
    '/downloads': (context) => const DownloadsPage(),
    '/data-management': (context) => const DataManagementPage(),
    '/about-version': (context) => const AboutVersionPage(),
    '/settings': (context) => const SettingsPage(),
    '/optional-plugin-settings': (context) =>
        const OptionalPluginSettingsPage(),
    '/local-http-settings': (context) =>
        const SettingsPage(initialSection: SettingsInitialSection.localHttp),
    '/browser-history': (context) => const BrowserHistoryPage(),
    '/simple-file-manager': (context) => const SimpleFileManagerSettingsPage(),
    '/easytier': (context) => const EasyTierSettingsPage(),
    '/remote-control': (context) => RemoteControlPage(
      service: RemoteControlService(),
      runtimeCoordinator: RemoteControlPageCoordinator(),
      platformRuntime: RemoteControlPlatformGateway.instance,
      runtimeLogger: AppLogService.instance,
      showMessage: AppToast.show,
      navigatorKey: AppToast.navigatorKey,
      ensureVoicePluginAvailable: () => OptionalFeatureGate().ensureAvailable(
        context,
        OptionalFeatureId.webRtcVoice,
      ),
      ensureEasyTierPluginAvailable: () => OptionalFeatureGate()
          .ensureAvailable(context, OptionalFeatureId.easyTier),
    ),
    '/telegram-checkin': (context) => const TelegramCheckinPage(),
    '/translation-tool': (context) => const TranslationToolPage(),
    '/ai-chat': (context) => const AiChatPage(),
    '/music-player': (context) => const MusicPlayerPage(),
    '/tools': (context) => const ToolsPage(),
    '/life-runtime': (context) => const LifeRuntimePage(),
  };
}
