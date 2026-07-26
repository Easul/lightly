import '../browser_settings_service.dart';
import '../../features/local_sharing/clipboard/clipboard_http_server_service.dart';
import '../../features/local_sharing/clipboard/clipboard_storage_service.dart';
import '../../features/local_sharing/local_http/local_http_file_server_service.dart';
import '../../features/proxy/infrastructure/proxy_service.dart';
import '../../services/app_cache_maintenance_service.dart';
import 'browser_download_service.dart';
import 'browser_download_store.dart';
import 'browser_cookie_origin_service.dart';
import 'browser_external_url_launcher_service.dart';
import 'browser_favorite_service.dart';
import 'browser_history_service.dart';
import 'browser_subscription_service.dart';
import 'browser_tab_service.dart';

class BrowserSharedServices {
  BrowserSharedServices._();

  static final BrowserSharedServices instance = BrowserSharedServices._();

  final BrowserSettingsService settingsService = BrowserSettingsService();
  final BrowserTabService tabService = BrowserTabService();
  final ProxyService proxyService = ProxyService();
  final BrowserHistoryService historyService = BrowserHistoryService();
  final BrowserCookieOriginService cookieOriginService =
      BrowserCookieOriginService();
  final BrowserDownloadService downloadService = BrowserDownloadService();
  final BrowserDownloadStore downloadStore = BrowserDownloadStore();
  final BrowserExternalUrlLauncherService externalUrlLauncher =
      BrowserExternalUrlLauncherService();
  final BrowserFavoriteService favoriteService = BrowserFavoriteService();
  final LocalHttpFileServerService localHttpFileServerService =
      LocalHttpFileServerService();
  final ClipboardHttpServerService clipboardService =
      ClipboardHttpServerService();
  final ClipboardStorageService clipboardStorage = ClipboardStorageService();
  final BrowserSubscriptionService subscriptionService =
      BrowserSubscriptionService();
  final AppCacheMaintenanceService appCacheMaintenanceService =
      AppCacheMaintenanceService();
}
