import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/app_theme.dart';
import '../browser/browser_settings.dart';
import '../browser/local_http_file_server_service.dart';
import '../browser/browser_settings_service.dart';
import '../browser/models/browser_tab_session.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_download_coordinator.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';
import '../browser/services/browser_external_app_handler.dart';
import '../browser/services/browser_external_url_launcher_service.dart';
import '../browser/services/browser_favorite_action_coordinator.dart';
import '../browser/services/browser_favorite_service.dart';
import '../browser/services/browser_favorite_status_tracker.dart';
import '../browser/services/browser_favorites_coordinator.dart';
import '../browser/services/browser_find_controller.dart';
import '../browser/services/browser_fullscreen_manager.dart';
import '../browser/services/browser_history_recorder.dart';
import '../browser/services/browser_history_service.dart';
import '../browser/services/browser_imported_document_service.dart';
import '../browser/services/browser_long_press_handler.dart';
import '../browser/services/browser_page_initializer.dart';
import '../browser/services/browser_popup_window_handler.dart';
import '../browser/services/browser_auth_dialog_service.dart';
import '../browser/services/browser_suggestion_service.dart';
import '../browser/services/browser_tab_coordinator.dart';
import '../browser/services/browser_tab_service.dart';
import '../browser/services/browser_video_detection_coordinator.dart';
import '../browser/services/browser_video_detection_tracker.dart';
import '../browser/services/browser_video_playback_preparation_service.dart';
import '../browser/services/browser_video_player_coordinator.dart';
import '../browser/utils/browser_popup_filter.dart';
import '../browser/services/video_proxy_server.dart';
import '../browser/utils/browser_url_utils.dart';
import '../browser/utils/ui_update_thresholds.dart';
import '../browser/widgets/browser_favorites_page.dart';
import '../browser/widgets/browser_favorites_menu_sheet.dart';
import '../browser/widgets/browser_find_in_page_sheet.dart';
import '../browser/widgets/browser_webview_host.dart';
import '../browser/clipboard_http_server_service.dart';
import '../browser/clipboard_storage_service.dart';
import '../widgets/app_drawer.dart';
import 'browser_page_action_coordinator.dart';
import 'browser_page_external_intent_helper.dart';
import 'browser_page_favorite_helper.dart';
import 'browser_page_modal_actions.dart';
import 'browser_page_settings_helper.dart';
import 'browser_page_site_security_helper.dart';
import 'browser_page_shell_widgets.dart';
import 'browser_page_status_coordinator.dart';
import 'browser_page_tab_transition_helper.dart';
import 'browser_page_tab_flow_coordinator.dart';
import 'browser_page_webview_coordinator.dart';
import 'browser_page_route_handler.dart';
import 'browser_site_security_dialogs.dart';
import 'browser_site_data_manager.dart';
import '../services/app_lifecycle_manager.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, this.enableWebView = true});

  final bool enableWebView;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _AppliedBrowserSettings {
  const _AppliedBrowserSettings({
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

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  late final BrowserPageServices _services;
  late final BrowserPageInitializer _initializer;
  final GlobalKey<BrowserFavoritesPageState> _favoritesPageKey =
      GlobalKey<BrowserFavoritesPageState>();
  final BrowserPageActionCoordinator _actionCoordinator =
      const BrowserPageActionCoordinator();
  final BrowserPageStatusCoordinator _statusCoordinator =
      const BrowserPageStatusCoordinator();
  final BrowserPageSettingsHelper _settingsHelper =
      const BrowserPageSettingsHelper();
  final BrowserPageSiteSecurityHelper _siteSecurityHelper =
      const BrowserPageSiteSecurityHelper();
  final BrowserPageTabFlowCoordinator _tabFlowCoordinator =
      const BrowserPageTabFlowCoordinator();
  final BrowserPageTabTransitionHelper _tabTransitionHelper =
      const BrowserPageTabTransitionHelper();
  final BrowserPageWebViewCoordinator _webViewCoordinator =
      const BrowserPageWebViewCoordinator();
  final BrowserPageRouteHandler _routeHandler = const BrowserPageRouteHandler();
  final BrowserSiteDataManager _siteDataManager =
      const BrowserSiteDataManager();
  final BrowserPageExternalIntentHelper _externalIntentHelper =
      const BrowserPageExternalIntentHelper();
  final BrowserPageFavoriteHelper _favoriteHelper =
      const BrowserPageFavoriteHelper();

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  BrowserSettingsService get _settingsService => _services.settingsService;
  BrowserTabService get _tabService => _services.tabService;
  BrowserFavoritesCoordinator get _favoritesCoordinator =>
      _services.favoritesCoordinator;
  ProxyService get _proxyService => _services.proxyService;
  BrowserHistoryService get _historyService => _services.historyService;
  BrowserImportedDocumentService get _importedDocumentService =>
      _services.importedDocumentService;
  BrowserDownloadService get _downloadService => _services.downloadService;
  BrowserDownloadStore get _downloadStore => _services.downloadStore;
  BrowserExternalUrlLauncherService get _externalUrlLauncher =>
      _services.externalUrlLauncher;
  BrowserDownloadCoordinator get _downloadCoordinator =>
      _services.downloadCoordinator;
  BrowserExternalAppHandler get _externalAppHandler =>
      _services.externalAppHandler;
  BrowserFavoriteStatusTracker get _favoriteStatusTracker =>
      _services.favoriteStatusTracker;
  BrowserFindController get _findController => _services.findController;
  BrowserFullscreenManager get _fullscreenManager =>
      _services.fullscreenManager;
  BrowserHistoryRecorder get _historyRecorder => _services.historyRecorder;
  BrowserLongPressHandler get _longPressHandler => _services.longPressHandler;
  BrowserPopupWindowHandler get _popupWindowHandler =>
      _services.popupWindowHandler;
  BrowserTabCoordinator get _tabCoordinator => _services.tabCoordinator;
  BrowserVideoDetectionCoordinator get _videoDetectionCoordinator =>
      _services.videoDetectionCoordinator;
  BrowserVideoPlayerCoordinator get _videoPlayerCoordinator =>
      _services.videoPlayerCoordinator;
  BrowserVideoPlaybackPreparationService get _videoPlaybackPreparationService =>
      _services.videoPlaybackPreparationService;
  BrowserFavoriteService get _favoriteService => _services.favoriteService;
  LocalHttpFileServerService get _localHttpFileServerService =>
      _services.localHttpFileServerService;
  ClipboardHttpServerService get _clipboardService =>
      _services.clipboardService;
  ClipboardStorageService get _clipboardStorage => _services.clipboardStorage;
  BrowserSuggestionService get _suggestionService =>
      _services.suggestionService;
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
  late final BrowserFavoriteActionCoordinator _favoriteActionCoordinator;

  InAppWebViewController? _webViewController;
  BrowserSettings _settings = BrowserSettings.defaults();
  String _statusMessage = '';
  bool _isInitialized = false;
  bool _proxySupported = false;
  bool _isProxyActive = false;
  int _progress = 0;
  final BrowserVideoDetectionTracker _videoDetectionTracker =
      BrowserVideoDetectionTracker();
  VideoProxyServer get _videoProxyServer => _services.videoProxyServer;
  PullToRefreshController? _pullToRefreshController;
  BrowserTabSession? get _activeTab => _tabCoordinator.activeTab;
  String? get _activeTabId => _tabCoordinator.activeTabId;
  List<BrowserTabSession> get _tabs => _tabCoordinator.tabs;
  String get _currentUrl => _tabCoordinator.currentUrl;
  bool get _isLoading => _tabCoordinator.isLoading;
  bool get _canGoBack => _tabCoordinator.canGoBack;
  bool get _canGoForward => _tabCoordinator.canGoForward;
  bool get _isSecure => _tabCoordinator.isSecure;

  bool _isFavoritesPage(String? url) =>
      _favoritesCoordinator.isFavoritesPage(url);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _services = BrowserPageServices.create(
      videoDetectionTracker: _videoDetectionTracker,
      onDebugLog: _logDebug,
      onShowSnackBar: _showSnackBar,
    );
    _initializer = BrowserPageInitializer(
      settingsService: _settingsService,
      tabService: _tabService,
      favoritesCoordinator: _favoritesCoordinator,
      importedDocumentService: _importedDocumentService,
      favoriteStatusTracker: _favoriteStatusTracker,
      videoDetectionCoordinator: _videoDetectionCoordinator,
      proxyService: _proxyService,
      localHttpFileServerService: _localHttpFileServerService,
      clipboardService: _clipboardService,
      clipboardStorage: _clipboardStorage,
    );
    _favoriteStatusTracker.currentStatus.addListener(
      _handleFavoriteStatusChanged,
    );
    if (InAppWebViewPlatform.instance != null) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: AppColors.primary,
          backgroundColor: AppColors.cardBackground,
          enabled: true,
        ),
        onRefresh: () async {
          await _webViewController?.reload();
        },
      );
      _findController.initialize();
    }
    _favoriteActionCoordinator = BrowserFavoriteActionCoordinator(
      favoriteService: _favoriteService,
    );
    _initialize();
    _setupExternalUrlListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_tabService.saveSessions());
      unawaited(_importedDocumentService.cleanupUnfavoritedImportedFiles());
    }
  }

  void _syncAddressBarForCurrentTab() {
    final nextText = _tabCoordinator.addressBarTextForCurrentTab();
    if (_addressController.text == nextText) {
      return;
    }
    _addressController.text = nextText;
  }

  Future<void> _showFavoritesHome({bool resetNavigationState = true}) async {
    _addressFocusNode.unfocus();
    _resetVideoDetectionState();
    _resetProgress();
    _tabCoordinator.trimAllBackgroundKeepAlives();
    _favoritesCoordinator.applyFavoritesHomeState(
      tabCoordinator: _tabCoordinator,
      tabService: _tabService,
    );
    _initializer.resetFavoritesHomeState();
    _syncAddressBarForCurrentTab();
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = _statusCoordinator.cleared();
    });
    if (resetNavigationState) {
      await _webViewController?.stopLoading();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_tabService.saveSessions());
    unawaited(_importedDocumentService.cleanupUnfavoritedImportedFiles());
    unawaited(_fullscreenManager.restorePortraitIfNeeded());
    _suggestionService.dispose();
    _addressController.dispose();
    _addressFocusNode.dispose();
    _progressNotifier.dispose();
    _favoriteStatusTracker.currentStatus.removeListener(
      _handleFavoriteStatusChanged,
    );
    _favoriteStatusTracker.dispose();
    unawaited(_videoPlayerCoordinator.dispose());
    _findController.dispose();
    _pullToRefreshController?.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    final hostedTabId = _activeTabId;
    return BrowserPageBodySection(
      isFavoritesPage: _isFavoritesPage(_currentUrl),
      favoritesChild: BrowserFavoritesPage(
        key: _favoritesPageKey,
        onOpenUrl: (url) async {
          await _loadAddress(url);
        },
      ),
      webViewChild: BrowserWebViewHost(
        key: ValueKey('webview-${_activeTabId ?? 'none'}'),
        enabled: widget.enableWebView,
        initialUrl: _currentUrl,
        keepAlive: _activeTab?.keepAlive,
        isLoading: _isLoading,
        progressListenable: _progressNotifier,
        onWebViewCreated: (controller) {
          if (!_isActiveTabId(hostedTabId)) {
            return;
          }
          _webViewController = controller;
          unawaited(_reapplyProxyAfterWebViewCreated());
        },
        shouldOverrideUrlLoading: _handleShouldOverrideUrlLoading,
        onLongPressHitTestResult: _handleLongPressHitTestResult,
        onEnterFullscreen: (_) {
          unawaited(_fullscreenManager.enterWebFullscreen());
        },
        onExitFullscreen: (_) {
          unawaited(_fullscreenManager.exitWebFullscreen());
        },
        onCreateWindow: (controller, createWindowAction) async {
          return _handleCreateWindow(controller, createWindowAction);
        },
        onDownloadStartRequest: _handleDownloadStart,
        onLoadStart: (controller, url) {
          if (hostedTabId == null) {
            return;
          }
          final didChangeLoading = _updateTabById(hostedTabId, isLoading: true);
          final didChangeProgress = _isActiveTabId(hostedTabId)
              ? _updateProgressIfNeeded(0)
              : false;
          if (mounted &&
              _webViewCoordinator.shouldClearStatusOnLoadStart(
                isActiveTab: _isActiveTabId(hostedTabId),
                currentStatusMessage: _statusMessage,
                didChangeProgress: didChangeProgress,
                didChangeLoading: didChangeLoading,
              )) {
            setState(() {
              _statusMessage = _statusCoordinator.cleared();
            });
          }
          _syncUrlForTabIfNeeded(hostedTabId, url?.toString());
        },
        onLoadStop: (controller, url) async {
          if (hostedTabId == null) {
            return;
          }
          if (!mounted) {
            return;
          }
          _pullToRefreshController?.endRefreshing();
          final didChangeLoading = _updateTabById(
            hostedTabId,
            isLoading: false,
          );
          final didChangeProgress = _isActiveTabId(hostedTabId)
              ? _updateProgressIfNeeded(100)
              : false;
          _syncUrlForTabIfNeeded(hostedTabId, url?.toString());

          final currentTitle =
              _tabCoordinator.tabById(hostedTabId)?.title ?? '';
          unawaited(_recordHistory(url, currentTitle));
          if (!mounted) {
            return;
          }
          if (_webViewCoordinator.shouldRebuildOnLoadStop(
            isActiveTab: _isActiveTabId(hostedTabId),
            didChangeProgress: didChangeProgress,
            didChangeTitle: false,
            didChangeLoading: didChangeLoading,
          )) {
            setState(() {});
          }

          unawaited(
            _completeLoadStopFollowUp(
              hostedTabId: hostedTabId,
              controller: controller,
              url: url,
            ),
          );

          final savedScroll =
              _tabCoordinator.tabById(hostedTabId)?.scrollPosition ?? 0;
          if (savedScroll > 0) {
            unawaited(
              controller.scrollTo(
                x: 0,
                y: savedScroll.toInt(),
                animated: false,
              ),
            );
          }
        },
        onProgressChanged: (controller, progress) {
          if (_isActiveTabId(hostedTabId)) {
            _updateProgressIfNeeded(progress);
          }
        },
        onReceivedError: (controller, request, error) {
          if (hostedTabId == null) {
            return;
          }
          if (!mounted) {
            return;
          }
          _pullToRefreshController?.endRefreshing();
          _updateTabById(hostedTabId, isLoading: false);
          if (!_isActiveTabId(hostedTabId)) {
            return;
          }
          final desc = error.description;
          final decision = _webViewCoordinator.decideErrorStatus(
            description: desc,
            blockedPopupStatus: _statusCoordinator.blockedPopup(),
            externalSchemeStatus: _statusCoordinator.externalAppContinuing(),
          );
          if (decision.action ==
              BrowserPageWebViewErrorAction.blockedByResponse) {
            unawaited(_handleBlockedByResponse(request.url));
            setState(() {
              _statusMessage = decision.statusMessage;
            });
            return;
          }
          if (decision.action == BrowserPageWebViewErrorAction.externalScheme) {
            final requestedUrl = request.url;
            if (!_isWebScheme(requestedUrl.scheme)) {
              unawaited(_confirmAndLaunchExternalUrl(requestedUrl));
            }
            setState(() {
              _statusMessage = decision.statusMessage;
            });
            return;
          }
          setState(() {
            _statusMessage = decision.statusMessage;
          });
        },
        onReceivedHttpAuthRequest: _handleHttpAuthRequest,
        onScrollChanged: (controller, x, y) {
          if (hostedTabId == null) {
            return;
          }
          _updateScrollPositionForTabIfNeeded(hostedTabId, y.toDouble());
        },
        onTitleChanged: (controller, title) {
          if (hostedTabId == null) {
            return;
          }
          final didChangeTitle = _updateTabById(
            hostedTabId,
            title: title ?? '',
          );
          if (mounted &&
              _webViewCoordinator.shouldRebuildOnTitleChanged(
                isActiveTab: _isActiveTabId(hostedTabId),
                didChangeTitle: didChangeTitle,
              )) {
            setState(() {});
          }
        },
        onUpdateVisitedHistory: (controller, url, isReload) {
          if (hostedTabId == null) {
            return;
          }
          final currentTabUrl = _tabCoordinator.tabById(hostedTabId)?.url;
          if (_isFavoritesPage(currentTabUrl)) {
            return;
          }
          if (_webViewCoordinator.shouldHandleVisitedHistoryForActiveTab(
            isActiveTab: _isActiveTabId(hostedTabId),
          )) {
            unawaited(_handleVisitedHistoryUpdate(controller, url));
          } else if (url != null &&
              _webViewCoordinator.shouldSyncVisitedHistoryForBackgroundTab(
                isActiveTab: _isActiveTabId(hostedTabId),
                isFavoritesPage: _isFavoritesPage(currentTabUrl),
                isWebScheme: _isWebScheme(url.scheme),
              )) {
            _updateTabById(hostedTabId, url: url.toString());
          }
        },
        pullToRefreshController: _pullToRefreshController,
        findInteractionController: _findController.interactionController,
      ),
      statusMessage: _statusMessage,
    );
  }

  Future<String?> _getInitialIntentUrl() async {
    return _externalIntentHelper.getInitialIntentUrl();
  }

  Future<String?> _prepareExternalIntentUrl(String? url) async {
    return _externalIntentHelper.prepareExternalIntentUrl(url);
  }

  void _setupExternalUrlListener() {
    BrowserPageExternalIntentHelper.browserProxyChannel.setMethodCallHandler((
      call,
    ) async {
      if (call.method == 'onNewIntentUrl') {
        final rawUrl = call.arguments['url'] as String?;
        final url = await _prepareExternalIntentUrl(rawUrl);
        if (url != null && url.isNotEmpty && mounted) {
          await _openNewTabWithUrl(url);
        }
      }
      return null;
    });
  }

  Future<void> _openNewTabWithUrl(String url) async {
    await _openTab(url, title: '', isExternallyOpened: true);
  }

  Future<void> _initialize() async {
    final appliedSettings = await _initializer.initialize(
      onRestoreSessions: () {
        return _tabService.restoreSessions(
          _favoritesCoordinator.favoritesPageUrl,
        );
      },
      onSyncAddressBar: _syncAddressBarForCurrentTab,
      onCheckFavoriteStatus: _checkFavoriteStatus,
      onStartClipboardServerAfterFrame: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_initializer.maybeStartClipboardServer());
        });
      },
      onReplaceSuggestionService: _replaceSuggestionService,
      enableWebView: widget.enableWebView,
      onGetInitialIntentUrl: _getInitialIntentUrl,
      onOpenExternalUrl: (url) => _openNewTabWithUrl(url),
    );

    if (!mounted) {
      return;
    }

    final snapshot = _settingsHelper.buildInitializedSnapshot(
      settings: appliedSettings.settings,
      proxySupported: appliedSettings.proxySupported,
      isProxyActive: appliedSettings.isProxyActive,
      statusMessage: appliedSettings.proxyStatusMessage,
    );
    _syncAddressBarForCurrentTab();
    _checkFavoriteStatus(_currentUrl);
    setState(() {
      _settings = snapshot.settings;
      _proxySupported = snapshot.proxySupported;
      _isProxyActive = snapshot.isProxyActive;
      _statusMessage = snapshot.statusMessage;
      _isInitialized = snapshot.isInitialized;
    });
  }

  Future<void> _reloadSettings() async {
    final appliedSettings = await _initializer.reloadSettings(
      onClearVideoPromptState: _initializer.clearVideoPromptState,
      onReplaceSuggestionService: _replaceSuggestionService,
      enableWebView: widget.enableWebView,
    );

    if (!mounted) {
      return;
    }

    _tabService.setFallbackUrl(_favoritesCoordinator.favoritesPageUrl);
    final snapshot = _settingsHelper.buildReloadedSnapshot(
      settings: appliedSettings.settings,
      proxySupported: appliedSettings.proxySupported,
      isProxyActive: appliedSettings.isProxyActive,
      statusMessage: appliedSettings.proxyStatusMessage,
      isInitialized: _isInitialized,
    );
    setState(() {
      _settings = snapshot.settings;
      _proxySupported = snapshot.proxySupported;
      _isProxyActive = snapshot.isProxyActive;
      _statusMessage = snapshot.statusMessage;
      _isInitialized = snapshot.isInitialized;
      _initializer.clearVideoPromptState();
    });

    await _favoriteStatusTracker.refreshStatus(
      _currentUrl,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _applyNativeVideoPlayerSettingToCurrentWebView(
          appliedSettings.settings.nativeVideoPlayerEnabled,
        ),
      );
    });
  }

  Future<void> _applyNativeVideoPlayerSettingToCurrentWebView(
    bool enabled,
  ) async {
    final controller = _webViewController;
    if (controller == null || _isFavoritesPage(_currentUrl)) {
      if (!enabled) {
        unawaited(_videoPlayerCoordinator.closeFloatingVideoPlayer());
      }
      return;
    }

    if (!enabled) {
      await _videoPlayerCoordinator.closeFloatingVideoPlayer();
      return;
    }

    _resetVideoDetectionState();
  }

  Future<BrowserPageAppliedSettings> _applySettingsRuntimeChanges({
    required BrowserSettings settings,
    required bool swallowLocalHttpErrors,
  }) async {
    return _initializer.applySettingsRuntimeChanges(
      settings: settings,
      swallowLocalHttpErrors: swallowLocalHttpErrors,
      onReplaceSuggestionService: _replaceSuggestionService,
      enableWebView: widget.enableWebView,
    );
  }

  Future<void> _loadAddress(String rawValue) async {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final target = _resolveInput(trimmed);
    if (await _tryHandleExplicitYoutubeInput(target)) {
      return;
    }

    final wasFavoritesPage = _isFavoritesPage(_currentUrl);
    _addressController.text = target;
    final didChangeUrl = _updateActiveTab(
      url: target,
      isExternallyOpened: false,
    );
    final activeTabId = _activeTabId;
    if (activeTabId != null) {
      if (wasFavoritesPage) {
        _tabService.resetKeepAlive(activeTabId, recreate: true);
      }
      _tabService.ensureKeepAlive(activeTabId);
    }
    _checkFavoriteStatus(target);
    if (_statusCoordinator.shouldClearAfterAddressLoad(
      wasFavoritesPage: wasFavoritesPage,
      didChangeUrl: didChangeUrl,
      currentStatusMessage: _statusMessage,
    )) {
      setState(() {
        _statusMessage = _statusCoordinator.cleared();
      });
    }

    final controller = _webViewController;
    if (!wasFavoritesPage && controller != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
    }
  }

  String _resolveInput(String input) {
    final maybeUrl = normalizeBrowserUrl(input);
    if (maybeUrl != null) {
      return maybeUrl;
    }

    final engine = _isProxyActive
        ? 'https://www.google.com/search?q='
        : 'https://www.baidu.com/s?wd=';
    return engine + Uri.encodeComponent(input);
  }

  bool _shouldOpenNativeVideoFromUrl(String url) {
    return _videoPlayerCoordinator.shouldOpenNativeVideoFromUrl(url, _settings);
  }

  Future<bool> _tryHandleExplicitYoutubeInput(String url) async {
    if (!_shouldOpenNativeVideoFromUrl(url)) {
      return false;
    }

    _addressFocusNode.unfocus();
    if (mounted &&
        _statusCoordinator.shouldShowYoutubeResolving(_statusMessage)) {
      setState(() {
        _statusMessage = _statusCoordinator.youtubeResolving();
      });
    }

    await _videoPlayerCoordinator.showFloatingVideoPlayer(
      context: context,
      url: url,
      settings: _settings,
      currentPageTitle: _activeTab?.title ?? '',
    );
    if (mounted) {
      setState(() {
        _statusMessage = _statusCoordinator.cleared();
      });
    }
    return true;
  }

  bool _shouldUseProxy([BrowserSettings? settings, bool? proxySupported]) {
    final effectiveSettings = settings ?? _settings;
    final effectiveProxySupported = proxySupported ?? _proxySupported;
    return effectiveSettings.shouldApplyProxy && effectiveProxySupported;
  }

  void _replaceSuggestionService() {
    _services.replaceSuggestionService();
  }

  Future<HttpAuthResponse?> _handleHttpAuthRequest(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    if (!mounted) {
      return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
    }
    return BrowserAuthDialogService.showAuthDialog(context, challenge);
  }

  bool _updateActiveTab({
    String? url,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
    bool? isExternallyOpened,
  }) {
    return _tabCoordinator.updateActiveTab(
      url: url,
      title: title,
      isLoading: isLoading,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      scrollPosition: scrollPosition,
      isExternallyOpened: isExternallyOpened,
    );
  }

  bool _updateTabById(
    String tabId, {
    String? url,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
  }) {
    return _tabCoordinator.updateTabById(
      tabId,
      url: url,
      title: title,
      isLoading: isLoading,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      scrollPosition: scrollPosition,
    );
  }

  bool _isActiveTabId(String? tabId) => _tabCoordinator.isActiveTabId(tabId);

  void _syncUrlForTabIfNeeded(String tabId, String? url) {
    final result = _tabCoordinator.syncUrlForTabIfNeeded(tabId, url);
    final nextUrl = result.currentUrl;
    if (!result.isActiveTab || nextUrl == null) {
      return;
    }
    if (result.didChangeUrl &&
        !_addressFocusNode.hasFocus &&
        _addressController.text != nextUrl) {
      _addressController.text = nextUrl;
    }
    _checkFavoriteStatus(nextUrl);
    if (mounted && result.didChangeSecureState) {
      setState(() {});
    }
  }

  bool _updateProgressIfNeeded(int progress) {
    if (!shouldUpdateWebProgress(_progress, progress)) {
      return false;
    }

    _progress = progress;
    _progressNotifier.value = progress;
    return true;
  }

  void _resetProgress() {
    _progress = 0;
    _progressNotifier.value = 0;
  }

  void _updateScrollPositionIfNeeded(double scrollPosition) {
    _tabCoordinator.updateActiveScrollPositionIfNeeded(scrollPosition);
  }

  void _updateScrollPositionForTabIfNeeded(
    String tabId,
    double scrollPosition,
  ) {
    _tabCoordinator.updateScrollPositionForTabIfNeeded(tabId, scrollPosition);
  }

  Future<void> _refreshNavigationState([
    InAppWebViewController? providedController,
  ]) async {
    final controller = providedController ?? _webViewController;
    if (controller == null || !mounted) {
      return;
    }

    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) {
      return;
    }

    if (_canGoBack == canGoBack && _canGoForward == canGoForward) {
      return;
    }

    _updateActiveTab(canGoBack: canGoBack, canGoForward: canGoForward);
    setState(() {});
  }

  Future<void> _refreshNavigationStateForTab(
    String tabId,
    InAppWebViewController controller,
  ) async {
    if (!mounted) {
      return;
    }

    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) {
      return;
    }

    final changed = _updateTabById(
      tabId,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    );
    if (changed && _activeTabId == tabId) {
      setState(() {});
    }
  }

  Future<void> _completeLoadStopFollowUp({
    required String hostedTabId,
    required InAppWebViewController controller,
    required WebUri? url,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }

    final results = await Future.wait<dynamic>([
      controller.getTitle(),
      controller.canGoBack(),
      controller.canGoForward(),
    ]);

    if (!mounted) {
      return;
    }

    final resolvedTitle = (results[0] as String?) ?? '';
    final canGoBack = results[1] as bool;
    final canGoForward = results[2] as bool;
    final previousTitle = _tabCoordinator.tabById(hostedTabId)?.title ?? '';
    final didChangeTitle = previousTitle != resolvedTitle;
    final didChangeNavigation = _updateTabById(
      hostedTabId,
      title: resolvedTitle,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    );

    if (resolvedTitle.isNotEmpty) {
      unawaited(_recordHistory(url, resolvedTitle));
    }

    if (!mounted) {
      return;
    }

    if ((didChangeTitle || didChangeNavigation) &&
        _activeTabId == hostedTabId) {
      setState(() {});
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).pushNamed('/settings');
    if (_routeHandler.shouldReloadSettingsAfterSettingsRoute(result)) {
      await _reloadSettings();
    }
  }

  Future<void> _openDownloads() async {
    await Navigator.of(context).pushNamed('/downloads');
  }

  Future<void> _toggleProxy() async {
    final latestSettings = await _settingsService.loadSettings();
    final newSettings = latestSettings.copyWith(
      proxyEnabled: !latestSettings.proxyEnabled,
    );
    await _settingsService.saveSettings(newSettings);
    final appliedSettings = await _applySettingsRuntimeChanges(
      settings: newSettings,
      swallowLocalHttpErrors: true,
    );
    if (!mounted) return;
    setState(() {
      _settings = appliedSettings.settings;
      _proxySupported = appliedSettings.proxySupported;
      _isProxyActive = appliedSettings.isProxyActive;
      _statusMessage = appliedSettings.proxyStatusMessage;
    });
    _replaceSuggestionService();
  }

  Future<void> _reapplyProxyAfterWebViewCreated() async {
    if (!_shouldUseProxy()) {
      return;
    }

    try {
      await _proxyService.applyProxy(_settings);
      if (!mounted) {
        return;
      }
      setState(() {
        _isProxyActive = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = _proxyService.describeError(error);
        _isProxyActive = false;
      });
    }
  }

  Future<bool> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    final requestedUrl = createWindowAction.request.url?.toString() ?? '';
    final decision = _popupWindowHandler.decide(
      requestedUrl: requestedUrl,
      sourceUrl:
          createWindowAction.sourceFrame?.request?.url?.toString() ??
          _currentUrl,
      hasGesture: createWindowAction.hasGesture == true,
      openNewWindowInTab: _settings.openNewWindowInTab,
    );

    switch (decision.action) {
      case BrowserPopupWindowAction.ignore:
        return false;
      case BrowserPopupWindowAction.external:
        final parsedRequestedUrl = Uri.tryParse(requestedUrl);
        if (parsedRequestedUrl != null) {
          await _confirmAndLaunchExternalUrl(parsedRequestedUrl);
        }
        return false;
      case BrowserPopupWindowAction.openTab:
        final initialUrl = decision.initialUrl;
        if (initialUrl != null && initialUrl.isNotEmpty) {
          await _openTab(
            initialUrl,
            statusMessage: _statusCoordinator.popupOpenedInNewTab(),
          );
        }
        return false;
      case BrowserPopupWindowAction.showPopup:
        await _popupWindowHandler.showPopupWindow(
          context: context,
          windowId: createWindowAction.windowId,
          initialUrl: decision.initialUrl,
          onStatus: (message) {
            _setStatusMessage(message);
          },
        );
        final statusMessage = decision.statusMessage;
        _setStatusMessage(
          _statusCoordinator.nextExternalStatus(
            externalStatusMessage: statusMessage,
            currentStatusMessage: _statusMessage,
          ),
        );
        return true;
    }
  }

  Future<void> _handleBlockedByResponse(Uri? requestedUrl) async {
    if (!mounted) {
      return;
    }
    final statusMessage = await _externalAppHandler.handleBlockedByResponse(
      context,
      requestedUrl,
      shouldSuppressPopupUrl: _shouldSuppressPopupUrl,
      launchExternalUrl: _externalUrlLauncher.launch,
    );
    _setStatusMessage(
      _statusCoordinator.nextExternalStatus(
        externalStatusMessage: statusMessage,
        currentStatusMessage: _statusMessage,
      ),
    );
  }

  Future<void> _confirmAndLaunchExternalUrl(Uri requestedUrl) async {
    if (!mounted) {
      return;
    }
    final statusMessage = await _externalAppHandler.confirmAndLaunchExternalUrl(
      context,
      requestedUrl,
      launchExternalUrl: _externalUrlLauncher.launch,
    );
    _setStatusMessage(
      _statusCoordinator.nextExternalStatus(
        externalStatusMessage: statusMessage,
        currentStatusMessage: _statusMessage,
      ),
    );
  }

  Future<void> _handleVisitedHistoryUpdate(
    InAppWebViewController controller,
    Uri? requestedUrl,
  ) async {
    if (requestedUrl == null) {
      return;
    }

    if (!_historyRecorder.shouldHandleVisitedHistoryUpdate(requestedUrl)) {
      return;
    }

    final urlString = requestedUrl.toString();

    if (_isWebScheme(requestedUrl.scheme)) {
      _syncUrlIfNeeded(urlString);
      await _refreshNavigationState(controller);
      return;
    }

    unawaited(_confirmAndLaunchExternalUrl(requestedUrl));
  }

  Future<void> _showSiteSecurityDialog() async {
    await _siteSecurityHelper.showSiteSecurityDialog(
      context: context,
      currentUrl: _currentUrl,
      isSecure: _isSecure,
      siteDataManager: _siteDataManager,
      onClearSiteData: _clearCurrentSiteData,
    );
  }

  Future<void> _clearCurrentSiteData(Uri currentUri) async {
    try {
      final successMessage = await _siteSecurityHelper.clearCurrentSiteData(
        currentUri: currentUri,
        context: context,
        siteDataManager: _siteDataManager,
        controller: _webViewController,
      );
      if (successMessage == null) {
        return;
      }
      _showSnackBar(successMessage);
    } catch (error) {
      _showSnackBar('清除站点数据失败: $error');
    }
  }

  Future<void> _openTab(
    String url, {
    String title = '',
    String statusMessage = '',
    bool isExternallyOpened = false,
  }) async {
    final tab = _tabCoordinator.openTab(
      url: url,
      title: title,
      isExternallyOpened: isExternallyOpened,
    );
    if (!mounted) {
      return;
    }
    await _tabTransitionHelper.prepareOpenedOrSwitchedTab(
      clearWebViewController: () {
        _webViewController = null;
      },
      unfocusAddressBar: _addressFocusNode.unfocus,
      resetVideoDetectionState: _resetVideoDetectionState,
      syncAddressBar: _syncAddressBarForCurrentTab,
      checkFavoriteStatus: _checkFavoriteStatus,
      url: tab.url,
      resetProgress: _resetProgress,
      clearStatus: () {
        if (mounted) {
          setState(() {
            _statusMessage = statusMessage;
          });
        }
      },
      syncTrackedScrollPosition:
          _tabCoordinator.syncTrackedScrollPositionWithActiveTab,
      syncTrackedScroll: false,
    );
  }

  void _setStatusMessage(String message) {
    if (!mounted || _statusMessage == message) {
      return;
    }
    setState(() {
      _statusMessage = message;
    });
  }

  Future<void> _openNewTab() async {
    await _openTab(_favoritesCoordinator.favoritesPageUrl);
  }

  Future<void> _switchToTab(String tabId) async {
    final didActivate = _tabCoordinator.activateTab(tabId);
    if (!didActivate) {
      return;
    }

    if (!mounted) {
      return;
    }
    await _tabTransitionHelper.prepareOpenedOrSwitchedTab(
      clearWebViewController: () {
        _webViewController = null;
      },
      unfocusAddressBar: _addressFocusNode.unfocus,
      resetVideoDetectionState: _resetVideoDetectionState,
      syncAddressBar: _syncAddressBarForCurrentTab,
      checkFavoriteStatus: _checkFavoriteStatus,
      url: _currentUrl,
      resetProgress: _resetProgress,
      clearStatus: () {
        if (mounted) {
          setState(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
      syncTrackedScrollPosition:
          _tabCoordinator.syncTrackedScrollPositionWithActiveTab,
      syncTrackedScroll: true,
    );
  }

  Future<void> _closeTab(String tabId) async {
    final previousActiveId = _activeTabId;
    final nextTab = _tabCoordinator.closeTab(tabId);
    if (!mounted) {
      return;
    }
    await _tabTransitionHelper.prepareClosedTab(
      clearWebViewController: () {
        _webViewController = null;
      },
      unfocusAddressBar: _addressFocusNode.unfocus,
      syncAddressBar: _syncAddressBarForCurrentTab,
      checkFavoriteStatus: _checkFavoriteStatus,
      url: nextTab.url,
      resetProgress: _resetProgress,
      clearStatus: () {
        if (mounted) {
          setState(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
    );

    final previousId = previousActiveId;
    if (previousId == null) {
      setState(() {});
      return;
    }
    final decision = _tabFlowCoordinator.decideCloseTabFollowUp(
      previousActiveId: previousId,
      nextTabId: nextTab.id,
    );
    if (decision.followUp == BrowserPageCloseTabFollowUp.switchToTab) {
      await _switchToTab(decision.nextTabId);
      return;
    }
    setState(() {});
  }

  Future<void> _handleBrowserBack() async {
    final controller = _webViewController;
    final canGoBack = controller != null ? await controller.canGoBack() : false;
    final decision = _tabFlowCoordinator.decideBackAction(
      hasActiveVideoOverlay: _videoPlayerCoordinator.hasActiveOverlay,
      isVideoFullscreen:
          _videoPlayerCoordinator.floatingVideoPlayerController.isFullscreen,
      isInWebFullscreen: _fullscreenManager.isInWebFullscreen,
      canGoBackInWebView: canGoBack,
      tabCount: _tabService.tabCount,
      activeTabId: _activeTabId,
      isActiveTabExternallyOpened: _activeTab?.isExternallyOpened ?? false,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
    );

    switch (decision.action) {
      case BrowserPageBackAction.exitVideoFullscreen:
        _videoPlayerCoordinator.floatingVideoPlayerController
            .exitFullscreenToDefault();
        return;
      case BrowserPageBackAction.closeVideoOverlay:
        await _videoPlayerCoordinator.closeFloatingVideoPlayer();
        return;
      case BrowserPageBackAction.exitWebFullscreen:
        await _fullscreenManager.exitWebFullscreen();
        return;
      case BrowserPageBackAction.goBackInWebView:
        if (controller != null) {
          await controller.goBack();
          await _refreshNavigationState(controller);
        }
        return;
      case BrowserPageBackAction.closeExternalTabAndExitApp:
        final externalTabId = decision.activeTabId;
        if (externalTabId != null) {
          await _closeTab(externalTabId);
        }
        if (mounted) {
          await AppLifecycleManager().shutdownAllServices();
          await SystemNavigator.pop();
        }
        return;
      case BrowserPageBackAction.closeActiveTab:
        final activeTabId = decision.activeTabId;
        if (activeTabId != null) {
          await _closeTab(activeTabId);
        }
        return;
      case BrowserPageBackAction.showFavoritesHome:
        await _showFavoritesHome();
        return;
      case BrowserPageBackAction.exitApp:
        if (mounted) {
          await AppLifecycleManager().shutdownAllServices();
          await SystemNavigator.pop();
        }
        return;
    }
  }

  Future<void> _closeCurrentTab() async {
    final activeTabId = _activeTabId;
    if (activeTabId == null) {
      return;
    }

    await _closeTab(activeTabId);
  }

  Future<void> _closeAllTabs() async {
    _tabCoordinator.closeAllTabs();

    if (!mounted) {
      return;
    }
    await _tabTransitionHelper.prepareCloseAllTabs(
      unfocusAddressBar: _addressFocusNode.unfocus,
      syncAddressBar: _syncAddressBarForCurrentTab,
      checkFavoriteStatus: _checkFavoriteStatus,
      url: _currentUrl,
      resetProgress: _resetProgress,
      clearStatus: () {
        if (mounted) {
          setState(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
    );
    unawaited(_tabService.saveSessions());
  }

  Future<void> _loadActiveTabIntoWebView() async {
    final controller = _webViewController;
    final activeTab = _activeTab;
    if (controller == null || activeTab == null) {
      return;
    }

    if (_tabFlowCoordinator.shouldShowFavoritesInsteadOfLoading(
      isFavoritesPage: _isFavoritesPage(activeTab.url),
    )) {
      await _showFavoritesHome(resetNavigationState: false);
      return;
    }

    _updateActiveTab(isLoading: true, canGoBack: false, canGoForward: false);
    if (mounted) {
      setState(() {});
    }

    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(activeTab.url)),
    );
  }

  Future<void> _handleVideoDetected(String? url) async {
    await _videoDetectionCoordinator.handleDetectedVideo(
      url,
      nativeVideoEnabled: _settings.nativeVideoPlayerEnabled,
      onOpenVideo: (normalizedUrl) async {
        _webViewController?.evaluateJavascript(
          source: "var v=document.querySelector('video'); if(v) v.pause();",
        );
        await _videoPlayerCoordinator.showFloatingVideoPlayer(
          context: context,
          url: normalizedUrl,
          settings: _settings,
          currentPageTitle: _activeTab?.title ?? '',
        );
      },
    );
  }

  void _injectVideoDetectionScript(InAppWebViewController controller) {
    if (!_videoDetectionCoordinator.shouldInjectScript(
      nativeVideoEnabled: _settings.nativeVideoPlayerEnabled,
    )) {
      return;
    }
    _videoDetectionCoordinator.markScriptInjected();
    controller.evaluateJavascript(
      source: _videoDetectionCoordinator.buildInjectionScript(),
    );
  }

  void _syncUrlIfNeeded(String? url) {
    final result = _tabCoordinator.syncActiveUrlIfNeeded(url);
    final nextUrl = result.currentUrl;
    if (nextUrl == null) {
      return;
    }
    if (result.didChangeUrl &&
        !_addressFocusNode.hasFocus &&
        _addressController.text != nextUrl) {
      _addressController.text = nextUrl;
    }
    _checkFavoriteStatus(nextUrl);
    if (mounted && result.didChangeSecureState) {
      setState(() {});
    }
  }

  void _handleFavoriteStatusChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _checkFavoriteStatus(String url) async {
    await _favoriteHelper.checkFavoriteStatus(
      tracker: _favoriteStatusTracker,
      url: url,
      isFavoritesPage: _isFavoritesPage(url),
    );
  }

  Future<void> _toggleFavorite() async {
    final url = _currentUrl;
    final title = _activeTab?.title ?? '';

    final result = await _favoriteHelper.toggleFavorite(
      coordinator: _favoriteActionCoordinator,
      tracker: _favoriteStatusTracker,
      url: url,
      title: title,
      isFavoritesPage: _isFavoritesPage(url),
    );
    if (result == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _resetVideoDetectionState() {
    _videoDetectionCoordinator.resetAll();
    _tabCoordinator.resetTrackedScrollPosition();
  }

  bool _isWebScheme(String? scheme) {
    return BrowserPopupFilter.isWebScheme(scheme);
  }

  bool _shouldSuppressPopupUrl(String? url) {
    return BrowserPopupFilter.shouldSuppressPopupUrl(url);
  }

  Future<void> _handleLongPressHitTestResult(
    InAppWebViewController controller,
    InAppWebViewHitTestResult result,
  ) async {
    final hitTestType = result.type;
    if (hitTestType == null) {
      return;
    }

    final request = _longPressHandler.createRequest(
      url: result.extra,
      type: hitTestType,
    );
    if (request == null) {
      return;
    }

    await _longPressHandler.showActions(
      context: context,
      request: request,
      nativeVideoPlayerEnabled: _settings.nativeVideoPlayerEnabled,
      onOpenInNewTab: (url) async {
        if (_isWebScheme(Uri.parse(url).scheme)) {
          final statusMessage = request.isYouTube
              ? (url == request.youtubeTargets?.mobileWatchUrl
                    ? '已在新标签页打开视频链接'
                    : url == request.youtubeTargets?.thumbnailUrl
                    ? '已在新标签页打开封面图'
                    : '已在新标签页打开原始视频链接')
              : '已在新标签页打开';
          await _openTab(url, statusMessage: statusMessage);
        }
      },
      onCopyToClipboard: _longPressHandler.copyToClipboard,
      onDownload: (url) async {
        await _downloadCoordinator.startDownloadFromUrl(
          context: context,
          url: url,
          settings: _settings,
          onStatus: _showSnackBar,
        );
      },
      onOpenOriginalVideo: (url) async {
        await _videoPlayerCoordinator.showFloatingVideoPlayer(
          context: context,
          url: url,
          settings: _settings,
          currentPageTitle: _activeTab?.title ?? '',
        );
      },
      onStatus: _showSnackBar,
    );
  }

  Future<NavigationActionPolicy> _handleShouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final requestedUrl = navigationAction.request.url;
    if (requestedUrl == null) {
      return NavigationActionPolicy.ALLOW;
    }

    final scheme = requestedUrl.scheme.toLowerCase();
    if (_isWebScheme(scheme)) {
      _syncUrlIfNeeded(requestedUrl.toString());
      return NavigationActionPolicy.ALLOW;
    }

    if (scheme == 'file') {
      return NavigationActionPolicy.ALLOW;
    }

    if (_externalAppHandler.isShowingExternalAppDialog) {
      return NavigationActionPolicy.CANCEL;
    }

    await _confirmAndLaunchExternalUrl(requestedUrl);

    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _showTabSwitcher() async {
    _tabCoordinator.trimKeepAlivesForOverlay();
    await Future<void>.delayed(Duration.zero);
    await showBrowserTabSwitcherModal(
      context: context,
      tabs: _tabs,
      activeTabId: _activeTabId,
      onSelectTab: _switchToTab,
      onCloseTab: _closeTab,
      onCloseAll: _closeAllTabs,
      onNewTab: _openNewTab,
    );
  }

  Future<void> _showMoreActions() async {
    await showBrowserMoreActionsModal(
      context: context,
      proxyEnabled: _settings.shouldApplyProxy,
      isFavorited: _favoriteStatusTracker.isCurrentPageFavorited,
      onToggleFavorite: _isFavoritesPage(_currentUrl) ? null : _toggleFavorite,
      onToggleProxy: _toggleProxy,
      onOpenDownloads: _openDownloads,
      onOpenDataManagement: _openDataManagement,
      onCloseTab: _closeCurrentTab,
      onOpenSettings: _openSettings,
      onExitApp: () async {
        await AppLifecycleManager().shutdownAllServices();
        await SystemNavigator.pop();
      },
      onOpenFavoritesMenu: _isFavoritesPage(_currentUrl)
          ? _showFavoritesMenu
          : null,
      onFindInPage: _showFindInPage,
    );
  }

  Future<void> _openDataManagement() async {
    final result = await Navigator.pushNamed(context, '/data-management');
    final plan = _routeHandler.planDataManagementActions(
      result: result,
      currentUrl: _currentUrl,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
    );
    await _actionCoordinator.applyDataManagementPlan(
      plan: plan,
      reloadSettings: _reloadSettings,
      showFavoritesHome: _showFavoritesHome,
      refreshFavorites: () async {
        await _favoritesPageKey.currentState?.refreshFavorites();
      },
      reloadCurrentWebView: () async {
        await _webViewController?.reload();
      },
      rebuild: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  Future<void> _showFavoritesMenu() async {
    final favoritesState = _favoritesPageKey.currentState;
    if (favoritesState == null) {
      return;
    }

    await showBrowserFavoritesMenuSheet(
      context: context,
      onAddFavorite: favoritesState.showAddFavoriteDialog,
      onToggleReorderMode: favoritesState.toggleReorderMode,
    );
  }

  Future<void> _showFindInPage() async {
    if (!_actionCoordinator.canShowFindInPage(
      isFindAvailable: _findController.isAvailable,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
    )) {
      return;
    }

    await showBrowserFindInPageSheet(
      context: context,
      findController: _findController,
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recordHistory(WebUri? url, String title) async {
    await _historyRecorder.recordHistory(url, title);
  }

  Future<void> _handleDownloadStart(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    await _downloadCoordinator.handleDownloadStart(
      context: context,
      request: request,
      settings: _settings,
      onStatus: _showSnackBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBrowserBack();
      },
      child: Scaffold(
        onDrawerChanged: (isOpen) {
          if (isOpen) {
            _tabCoordinator.trimKeepAlivesForOverlay();
          }
        },
        drawer: AppDrawer(onOpenSettings: _openSettings),
        appBar: BrowserPageAppBar(
          addressController: _addressController,
          addressFocusNode: _addressFocusNode,
          isSecure: _isSecure,
          suggestionService: _suggestionService,
          onSecurityPressed: _showSiteSecurityDialog,
          onClear: _addressController.clear,
          currentUrl: _currentUrl,
          onSubmitted: (value) async {
            await _loadAddress(value);
            _addressFocusNode.unfocus();
          },
          isLoading: _isLoading,
          onRefresh: () async {
            if (_isLoading) {
              await _webViewController?.stopLoading();
              _updateActiveTab(isLoading: false);
              if (mounted) {
                setState(() {});
              }
              return;
            }
            await _webViewController?.reload();
          },
        ),
        body: !_isInitialized
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
        bottomNavigationBar: BrowserPageBottomBar(
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
          isLoading: _isLoading,
          tabCount: _tabService.tabCount,
          proxyEnabled: _settings.shouldApplyProxy,
          onBack: _handleBrowserBack,
          onForward: () async => _webViewController?.goForward(),
          onHome: _showFavoritesHome,
          onOpenTabs: _showTabSwitcher,
          onOpenMoreActions: _showMoreActions,
          onFindInPage: _showFindInPage,
        ),
      ),
    );
  }
}
