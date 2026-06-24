import 'package:flutter/foundation.dart';

import '../browser_settings.dart';
import '../browser_settings_service.dart';
import '../clipboard_http_server_service.dart';
import '../clipboard_storage_service.dart';
import '../local_http_file_server_service.dart';
import '../proxy_service.dart';
import '../../services/app_cache_maintenance_service.dart';
import 'browser_download_coordinator.dart';
import 'browser_cookie_origin_service.dart';
import 'browser_download_service.dart';
import 'browser_download_store.dart';
import 'browser_external_app_handler.dart';
import 'browser_external_url_launcher_service.dart';
import 'browser_favorite_service.dart';
import 'browser_favorites_coordinator.dart';
import 'browser_favorite_status_tracker.dart';
import 'browser_fullscreen_manager.dart';
import 'browser_history_recorder.dart';
import 'browser_history_service.dart';
import 'browser_imported_document_service.dart';
import 'browser_long_press_handler.dart';
import 'browser_popup_window_handler.dart';
import 'browser_shared_services.dart';
import 'browser_suggestion_service.dart';
import 'browser_tab_coordinator.dart';
import 'browser_video_detection_coordinator.dart';
import 'browser_video_detection_tracker.dart';
import 'browser_video_player_coordinator.dart';
import 'browser_video_playback_preparation_service.dart';
import 'browser_tab_service.dart';
import 'external_api_video_source_resolver.dart';
import 'video_proxy_server.dart';

class BrowserPageServices {
  BrowserPageServices._({
    required this.settingsService,
    required this.tabService,
    required this.favoritesCoordinator,
    required this.proxyService,
    required this.historyService,
    required this.cookieOriginService,
    required this.downloadService,
    required this.downloadStore,
    required this.externalUrlLauncher,
    required this.favoriteService,
    required this.importedDocumentService,
    required this.localHttpFileServerService,
    required this.clipboardService,
    required this.clipboardStorage,
    required this.videoProxyServer,
    required this.downloadCoordinator,
    required this.externalAppHandler,
    required this.favoriteStatusTracker,
    required this.fullscreenManager,
    required this.historyRecorder,
    required this.longPressHandler,
    required this.popupWindowHandler,
    required this.tabCoordinator,
    required this.videoDetectionCoordinator,
    required this.videoPlaybackPreparationService,
    required this.videoPlayerCoordinator,
    required this.suggestionService,
  });

  factory BrowserPageServices.create({
    required BrowserVideoDetectionTracker videoDetectionTracker,
    required void Function(String) onDebugLog,
    required void Function(String) onShowSnackBar,
  }) {
    final sharedServices = BrowserSharedServices.instance;
    final settingsService = sharedServices.settingsService;
    final tabService = sharedServices.tabService;
    const favoritesCoordinator = BrowserFavoritesCoordinator();
    final proxyService = sharedServices.proxyService;
    final historyService = sharedServices.historyService;
    final cookieOriginService = sharedServices.cookieOriginService;
    final downloadService = sharedServices.downloadService;
    final downloadStore = sharedServices.downloadStore;
    final externalUrlLauncher = sharedServices.externalUrlLauncher;
    final favoriteService = sharedServices.favoriteService;
    final importedDocumentService = BrowserImportedDocumentService(
      favoriteService: favoriteService,
    );
    final localHttpFileServerService =
        sharedServices.localHttpFileServerService;
    final clipboardService = sharedServices.clipboardService;
    final clipboardStorage = sharedServices.clipboardStorage;
    final videoProxyServer = VideoProxyServer();
    final tabCoordinator = BrowserTabCoordinator(
      tabService: tabService,
      favoritesPageUrl: favoritesCoordinator.favoritesPageUrl,
    );
    final favoriteStatusTracker = BrowserFavoriteStatusTracker(
      favoriteService: favoriteService,
    );
    final fullscreenManager = BrowserFullscreenManager();
    final videoDetectionCoordinator = BrowserVideoDetectionCoordinator(
      tracker: videoDetectionTracker,
    );
    final historyRecorder = BrowserHistoryRecorder(
      historyService: historyService,
    );
    final longPressHandler = BrowserLongPressHandler();
    final popupWindowHandler = BrowserPopupWindowHandler();
    final externalAppHandler = BrowserExternalAppHandler();
    final downloadCoordinator = BrowserDownloadCoordinator(
      downloadService: downloadService,
      downloadStore: downloadStore,
      proxyService: proxyService,
    );
    final videoPlaybackPreparationService =
        BrowserVideoPlaybackPreparationService(
          loadSettings: settingsService.loadSettings,
          resolveVideoSource: (url, settings) {
            final resolver = ExternalApiVideoSourceResolver(
              apiBaseUrl: settings.normalizedNativeVideoParserApiBaseUrl,
              proxyService: proxyService,
              settings: settings,
            );
            return resolver.resolve(url);
          },
          ensureProxyServer: (settings) {
            return videoProxyServer.start(
              proxyService: proxyService,
              settings: settings,
            );
          },
          buildProxyPlaybackUrl: videoProxyServer.buildProxyUrl,
          redactDownloadUrl: BrowserDownloadCoordinator.redactDownloadUrl,
          onDebugLog: onDebugLog,
        );
    final videoPlayerCoordinator = BrowserVideoPlayerCoordinator(
      playbackPreparationService: videoPlaybackPreparationService,
      downloadCoordinator: downloadCoordinator,
      videoDetectionTracker: videoDetectionTracker,
      stopProxyServer: videoProxyServer.stop,
      onShowSnackBar: onShowSnackBar,
      onDebugLog: onDebugLog,
    );

    return BrowserPageServices._(
      settingsService: settingsService,
      tabService: tabService,
      favoritesCoordinator: favoritesCoordinator,
      proxyService: proxyService,
      historyService: historyService,
      cookieOriginService: cookieOriginService,
      downloadService: downloadService,
      downloadStore: downloadStore,
      externalUrlLauncher: externalUrlLauncher,
      favoriteService: favoriteService,
      importedDocumentService: importedDocumentService,
      localHttpFileServerService: localHttpFileServerService,
      clipboardService: clipboardService,
      clipboardStorage: clipboardStorage,
      videoProxyServer: videoProxyServer,
      downloadCoordinator: downloadCoordinator,
      externalAppHandler: externalAppHandler,
      favoriteStatusTracker: favoriteStatusTracker,
      fullscreenManager: fullscreenManager,
      historyRecorder: historyRecorder,
      longPressHandler: longPressHandler,
      popupWindowHandler: popupWindowHandler,
      tabCoordinator: tabCoordinator,
      videoDetectionCoordinator: videoDetectionCoordinator,
      videoPlaybackPreparationService: videoPlaybackPreparationService,
      videoPlayerCoordinator: videoPlayerCoordinator,
      suggestionService: BrowserSuggestionService(),
    );
  }

  final BrowserSettingsService settingsService;
  final BrowserTabService tabService;
  final BrowserFavoritesCoordinator favoritesCoordinator;
  final ProxyService proxyService;
  final BrowserHistoryService historyService;
  final BrowserCookieOriginService cookieOriginService;
  final BrowserDownloadService downloadService;
  final BrowserDownloadStore downloadStore;
  final BrowserExternalUrlLauncherService externalUrlLauncher;
  final BrowserFavoriteService favoriteService;
  final BrowserImportedDocumentService importedDocumentService;
  final LocalHttpFileServerService localHttpFileServerService;
  final ClipboardHttpServerService clipboardService;
  final ClipboardStorageService clipboardStorage;
  final VideoProxyServer videoProxyServer;
  final BrowserDownloadCoordinator downloadCoordinator;
  final BrowserExternalAppHandler externalAppHandler;
  final BrowserFavoriteStatusTracker favoriteStatusTracker;
  final BrowserFullscreenManager fullscreenManager;
  final BrowserHistoryRecorder historyRecorder;
  final BrowserLongPressHandler longPressHandler;
  final BrowserPopupWindowHandler popupWindowHandler;
  final BrowserTabCoordinator tabCoordinator;
  final BrowserVideoDetectionCoordinator videoDetectionCoordinator;
  final BrowserVideoPlaybackPreparationService videoPlaybackPreparationService;
  final BrowserVideoPlayerCoordinator videoPlayerCoordinator;
  BrowserSuggestionService suggestionService;

  void replaceSuggestionService() {
    suggestionService.dispose();
    suggestionService = BrowserSuggestionService();
  }

  void dispose() {
    suggestionService.dispose();
    favoriteStatusTracker.dispose();
  }
}

class BrowserPageAppliedSettings {
  const BrowserPageAppliedSettings({
    required this.settings,
    required this.proxySupported,
    required this.isProxyActive,
    required this.proxyStatusMessage,
  });

  final BrowserSettings settings;
  final bool proxySupported;
  final bool isProxyActive;
  final String proxyStatusMessage;
}

class BrowserPageInitializer {
  BrowserPageInitializer({
    required BrowserSettingsService settingsService,
    required BrowserTabService tabService,
    required BrowserFavoritesCoordinator favoritesCoordinator,
    required BrowserImportedDocumentService importedDocumentService,
    required BrowserFavoriteStatusTracker favoriteStatusTracker,
    required BrowserVideoDetectionCoordinator videoDetectionCoordinator,
    required ProxyService proxyService,
    required LocalHttpFileServerService localHttpFileServerService,
    required ClipboardHttpServerService clipboardService,
    required ClipboardStorageService clipboardStorage,
    required AppCacheMaintenanceService appCacheMaintenanceService,
  }) : _settingsService = settingsService,
       _tabService = tabService,
       _favoritesCoordinator = favoritesCoordinator,
       _importedDocumentService = importedDocumentService,
       _favoriteStatusTracker = favoriteStatusTracker,
       _videoDetectionCoordinator = videoDetectionCoordinator,
       _proxyService = proxyService,
       _localHttpFileServerService = localHttpFileServerService,
       _clipboardService = clipboardService,
       _clipboardStorage = clipboardStorage,
       _appCacheMaintenanceService = appCacheMaintenanceService;

  final BrowserSettingsService _settingsService;
  final BrowserTabService _tabService;
  final BrowserFavoritesCoordinator _favoritesCoordinator;
  final BrowserImportedDocumentService _importedDocumentService;
  final BrowserFavoriteStatusTracker _favoriteStatusTracker;
  final BrowserVideoDetectionCoordinator _videoDetectionCoordinator;
  final ProxyService _proxyService;
  final LocalHttpFileServerService _localHttpFileServerService;
  final ClipboardHttpServerService _clipboardService;
  final ClipboardStorageService _clipboardStorage;
  final AppCacheMaintenanceService _appCacheMaintenanceService;

  Future<BrowserPageAppliedSettings> initialize({
    required Future<void> Function() onRestoreSessions,
    required VoidCallback onSyncAddressBar,
    required Future<void> Function(String url) onCheckFavoriteStatus,
    required VoidCallback onStartClipboardServerAfterFrame,
    required VoidCallback onReplaceSuggestionService,
    required bool enableWebView,
    Future<String?> Function()? onGetInitialIntentUrl,
    required void Function(String url) onOpenExternalUrl,
  }) async {
    final settingsFuture = _settingsService.loadSettings();
    final restoreSessionsFuture = onRestoreSessions();
    final cleanupImportedFilesFuture = _importedDocumentService
        .cleanupUnfavoritedImportedFiles();
    _tabService.setFallbackUrl(_favoritesCoordinator.favoritesPageUrl);

    final settings = await settingsFuture;
    try {
      await _appCacheMaintenanceService.maybeAutoClear(settings);
    } catch (_) {}
    final appliedSettingsFuture = applySettingsRuntimeChanges(
      settings: settings,
      swallowLocalHttpErrors: true,
      onReplaceSuggestionService: onReplaceSuggestionService,
      enableWebView: enableWebView,
    );
    await restoreSessionsFuture;
    await cleanupImportedFilesFuture;
    final appliedSettings = await appliedSettingsFuture;

    final externalUrl = onGetInitialIntentUrl != null
        ? await onGetInitialIntentUrl()
        : null;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      onOpenExternalUrl(externalUrl);
    }

    onSyncAddressBar();
    await onCheckFavoriteStatus(
      _tabService.activeTab?.url ?? _favoritesCoordinator.favoritesPageUrl,
    );
    onStartClipboardServerAfterFrame();
    return appliedSettings;
  }

  Future<BrowserPageAppliedSettings> reloadSettings({
    required VoidCallback onClearVideoPromptState,
    required VoidCallback onReplaceSuggestionService,
    required bool enableWebView,
  }) async {
    final appliedSettings = await applySettingsRuntimeChanges(
      settings: await _settingsService.loadSettings(),
      swallowLocalHttpErrors: true,
      onReplaceSuggestionService: onReplaceSuggestionService,
      enableWebView: enableWebView,
    );

    _tabService.setFallbackUrl(_favoritesCoordinator.favoritesPageUrl);
    onClearVideoPromptState();
    return appliedSettings;
  }

  Future<BrowserPageAppliedSettings> applySettingsRuntimeChanges({
    required BrowserSettings settings,
    required bool swallowLocalHttpErrors,
    required VoidCallback onReplaceSuggestionService,
    required bool enableWebView,
  }) async {
    final proxySupported = enableWebView && !kIsWeb
        ? await _proxyService.isSupported().catchError((_) => false)
        : false;
    var proxyStatusMessage = '';
    var isProxyActive = false;

    if (proxySupported) {
      if (_shouldUseProxy(settings, proxySupported)) {
        try {
          await _proxyService.applyProxy(settings);
          isProxyActive = true;
        } catch (error) {
          proxyStatusMessage = _proxyService.describeError(error);
        }
      } else {
        try {
          await _proxyService.clearProxy();
        } catch (error) {
          proxyStatusMessage = _proxyService.describeError(error);
        }
      }
    }

    try {
      await _localHttpFileServerService.applySettings(settings);
    } catch (_) {
      if (!swallowLocalHttpErrors) {
        rethrow;
      }
    }

    onReplaceSuggestionService();
    return BrowserPageAppliedSettings(
      settings: settings,
      proxySupported: proxySupported,
      isProxyActive: isProxyActive,
      proxyStatusMessage: proxyStatusMessage,
    );
  }

  Future<void> maybeStartClipboardServer() async {
    try {
      final enabled = await _clipboardStorage.loadServerEnabled();
      if (!enabled || _clipboardService.isRunning) {
        return;
      }
      final port = await _clipboardStorage.loadServerPort();
      await _clipboardService.start(preferredPort: port);
    } catch (_) {}
  }

  bool _shouldUseProxy(BrowserSettings settings, bool proxySupported) {
    return settings.shouldApplyProxy && proxySupported;
  }

  void resetFavoritesHomeState() {
    _favoriteStatusTracker.resetForFavoritesPage();
  }

  void clearVideoPromptState() {
    _videoDetectionCoordinator.clearPromptStateForSettingsChange();
  }
}
