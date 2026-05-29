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
import '../browser/services/browser_cookie_origin_service.dart';
import '../browser/services/browser_external_app_handler.dart';
import '../browser/services/browser_external_url_launcher_service.dart';
import '../browser/services/browser_favorite_status_controller.dart';
import '../browser/services/browser_favorite_service.dart';
import '../browser/services/browser_favorite_status_tracker.dart';
import '../browser/services/browser_favorites_coordinator.dart';
import '../browser/services/browser_find_controller.dart';
import '../browser/services/browser_fullscreen_manager.dart';
import '../browser/services/browser_history_recorder.dart';
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
import '../browser/services/browser_video_player_coordinator.dart';
import '../services/app_toast.dart';
import '../browser/utils/ui_update_thresholds.dart';
import '../browser/utils/browser_site_compatibility_script.dart';
import '../browser/widgets/browser_favorites_page.dart';
import '../browser/widgets/browser_webview_host.dart';
import '../browser/clipboard_http_server_service.dart';
import '../browser/clipboard_storage_service.dart';
import '../widgets/app_drawer.dart';
import 'browser_page_address_sync.dart';
import 'browser_page_address_bar_coordinator.dart';
import 'browser_page_action_coordinator.dart';
import 'browser_page_external_intent_helper.dart';
import 'browser_page_lifecycle_coordinator.dart';
import 'browser_page_modal_coordinator.dart';
import 'browser_page_notifier_sync.dart';
import 'browser_page_overlay_state_manager.dart';
import 'browser_page_settings_helper.dart';
import 'browser_page_site_security_helper.dart';
import 'browser_page_shell_widgets.dart';
import 'browser_page_input_resolver.dart';
import 'browser_page_state_predicates.dart';
import 'browser_page_status_coordinator.dart';
import 'browser_page_tab_transition_helper.dart';
import 'browser_page_tab_transition_coordinator.dart';
import 'browser_page_tab_flow_coordinator.dart';
import 'browser_page_url_filter_helper.dart';
import 'browser_page_webview_lifecycle_helper.dart';
import 'browser_page_webview_coordinator.dart';
import 'browser_page_route_handler.dart';
import 'browser_site_data_manager.dart';
import '../services/app_lifecycle_manager.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, this.enableWebView = true});

  final bool enableWebView;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  late final BrowserPageServices _services;
  late final BrowserPageInitializer _initializer;
  final GlobalKey<BrowserFavoritesPageState> _favoritesPageKey =
      GlobalKey<BrowserFavoritesPageState>();
  final BrowserPageActionCoordinator _actionCoordinator =
      const BrowserPageActionCoordinator();
  final BrowserPageAddressBarCoordinator _addressBarCoordinator =
      const BrowserPageAddressBarCoordinator();
  final BrowserPageModalCoordinator _modalCoordinator =
      const BrowserPageModalCoordinator();
  final BrowserPageStatusCoordinator _statusCoordinator =
      const BrowserPageStatusCoordinator();
  final BrowserPageSettingsHelper _settingsHelper =
      const BrowserPageSettingsHelper();
  final BrowserPageSiteSecurityHelper _siteSecurityHelper =
      const BrowserPageSiteSecurityHelper();
  final BrowserPageTabFlowCoordinator _tabFlowCoordinator =
      const BrowserPageTabFlowCoordinator();
  final BrowserPageTabTransitionCoordinator _tabTransitionCoordinator =
      const BrowserPageTabTransitionCoordinator();
  final BrowserPageWebViewCoordinator _webViewCoordinator =
      const BrowserPageWebViewCoordinator();
  final BrowserPageRouteHandler _routeHandler = const BrowserPageRouteHandler();
  final BrowserSiteDataManager _siteDataManager =
      const BrowserSiteDataManager();
  final BrowserPageExternalIntentHelper _externalIntentHelper =
      const BrowserPageExternalIntentHelper();
  final BrowserPageLifecycleCoordinator _lifecycleCoordinator =
      const BrowserPageLifecycleCoordinator();
  final BrowserPageWebViewLifecycleHelper _webViewLifecycleHelper =
      const BrowserPageWebViewLifecycleHelper();
  final BrowserPageUrlFilterHelper _urlFilterHelper =
      const BrowserPageUrlFilterHelper();
  final BrowserPageStatePredicates _statePredicates =
      const BrowserPageStatePredicates();
  final BrowserPageNotifierSync _notifierSync = const BrowserPageNotifierSync();
  final BrowserPageAddressSync _addressSync = const BrowserPageAddressSync();
  late final BrowserPageOverlayStateManager _overlayStateManager;

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
  BrowserImportedDocumentService get _importedDocumentService =>
      _services.importedDocumentService;
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
  BrowserCookieOriginService get _cookieOriginService =>
      _services.cookieOriginService;
  BrowserLongPressHandler get _longPressHandler => _services.longPressHandler;
  BrowserPopupWindowHandler get _popupWindowHandler =>
      _services.popupWindowHandler;
  BrowserTabCoordinator get _tabCoordinator => _services.tabCoordinator;
  BrowserVideoDetectionCoordinator get _videoDetectionCoordinator =>
      _services.videoDetectionCoordinator;
  BrowserVideoPlayerCoordinator get _videoPlayerCoordinator =>
      _services.videoPlayerCoordinator;
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
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canGoBackNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canGoForwardNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSecureNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> _tabCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String> _statusMessageNotifier = ValueNotifier<String>(
    '',
  );
  late final BrowserFavoriteStatusController _favoriteStatusController;

  InAppWebViewController? _webViewController;
  BrowserSettings _settings = BrowserSettings.defaults();
  String _statusMessage = '';
  bool _isInitialized = false;
  bool _proxySupported = false;
  bool _isProxyActive = false;
  int _progress = 0;
  final BrowserVideoDetectionTracker _videoDetectionTracker =
      BrowserVideoDetectionTracker();
  PullToRefreshController? _pullToRefreshController;
  BrowserTabSession? get _activeTab => _tabCoordinator.activeTab;
  String? get _activeTabId => _tabCoordinator.activeTabId;
  List<BrowserTabSession> get _tabs => _tabCoordinator.tabs;
  String get _currentUrl => _tabCoordinator.currentUrl;
  bool get _isLoading => _tabCoordinator.isLoading;
  bool get _canGoBack => _tabCoordinator.canGoBack;
  bool get _canGoForward => _tabCoordinator.canGoForward;
  bool get _isSecure => _tabCoordinator.isSecure;

  bool _isFavoritesPage(String? url) => _statePredicates.isFavoritesPage(
    favoritesCoordinator: _favoritesCoordinator,
    url: url,
  );

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
    _favoriteStatusController = BrowserFavoriteStatusController(
      tracker: _favoriteStatusTracker,
      favoriteService: _favoriteService,
      onStatusChanged: _handleFavoriteStatusChanged,
    );
    _overlayStateManager = BrowserPageOverlayStateManager(
      coordinator: _lifecycleCoordinator,
      isMounted: () => mounted,
      syncNotifiers: _syncNotifiers,
      rebuild: () => setState(() {}),
      pauseWebView: ({required trimKeepAlives}) {
        _pauseWebViewForOverlay(trimKeepAlives: trimKeepAlives);
      },
      resumeWebView: _resumeWebViewFromOverlay,
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
    _initialize();
    _setupExternalUrlListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_tabService.saveSessions());
      unawaited(_importedDocumentService.cleanupUnfavoritedImportedFiles());
    } else if (state == AppLifecycleState.resumed) {
      // Defensive: if the app went to background while an overlay was open,
      // the overlay may have been dismissed by the system without calling
      // _handleOverlayClosed. Force-resume timers so browsing isn't stuck.
      _overlayStateManager.handleAppResumed();
    }
  }

  void _pauseWebViewForOverlay({bool trimKeepAlives = true}) {
    _webViewLifecycleHelper.pauseForOverlay(
      pauseTimers: () {
        _webViewController?.pauseTimers();
      },
      pauseWebView: () {
        _webViewController?.pause();
      },
      evaluateJavascript: (source) {
        _webViewController?.evaluateJavascript(source: source);
      },
      trimKeepAlives: () {
        if (trimKeepAlives) {
          _tabCoordinator.trimKeepAlivesForOverlay();
        }
      },
    );
  }

  void _resumeWebViewFromOverlay() {
    _webViewLifecycleHelper.resumeFromOverlay(
      resumeTimers: () {
        _webViewController?.resumeTimers();
      },
      resumeWebView: () {
        _webViewController?.resume();
      },
      evaluateJavascript: (source) {
        _webViewController?.evaluateJavascript(source: source);
      },
    );
  }

  void _handleOverlayOpened({
    bool trimKeepAlives = true,
    bool pauseWebView = true,
  }) {
    _overlayStateManager.handleOverlayOpened(
      trimKeepAlives: trimKeepAlives,
      pauseWebView: pauseWebView,
    );
  }

  void _handleOverlayClosed() {
    _overlayStateManager.handleOverlayClosed();
  }

  Future<void> _runTrackedOverlayAction(Future<void> Function() action) async {
    await _overlayStateManager.runTrackedOverlayAction(action);
  }

  void _rebuildWhenVisible() {
    if (_shouldSkipRebuild) {
      _overlayStateManager.markDeferredOverlayRebuild();
    } else if (mounted) {
      _syncNotifiers();
      setState(() {});
    }
  }

  void _updateStateWhenVisible(VoidCallback fn) {
    if (_shouldSkipRebuild) {
      fn();
      _syncNotifiers();
      _overlayStateManager.markDeferredOverlayRebuild();
    } else if (mounted) {
      fn();
      _syncNotifiers();
      setState(() {});
    }
  }

  /// Whether setState calls for non-critical UI updates should be skipped.
  /// During overlay animations (drawer, bottom sheet), skipping rebuilds
  /// reduces jank by preventing the entire BrowserPage widget tree from
  /// rebuilding while the GPU is already busy compositing the overlay.
  bool get _shouldSkipRebuild => _overlayStateManager.shouldSkipRebuild;

  bool get _shouldFreezeWebViewForOverlay =>
      _overlayStateManager.shouldFreezeWebView;

  /// Calls setState only if the overlay is closed (critical period avoidance).
  /// State data is always updated; only the rebuild is deferred.
  void _setStateIfVisible(VoidCallback fn) {
    _updateStateWhenVisible(fn);
  }

  void _syncNotifiers() {
    _notifierSync.sync(
      isLoadingNotifier: _isLoadingNotifier,
      isLoading: _isLoading,
      canGoBackNotifier: _canGoBackNotifier,
      canGoBack: _canGoBack,
      canGoForwardNotifier: _canGoForwardNotifier,
      canGoForward: _canGoForward,
      isSecureNotifier: _isSecureNotifier,
      isSecure: _isSecure,
      tabCountNotifier: _tabCountNotifier,
      tabCount: _tabService.tabCount,
      statusMessageNotifier: _statusMessageNotifier,
      statusMessage: _statusMessage,
    );
  }

  void _syncAddressBarForCurrentTab() {
    _addressSync.syncForCurrentTab(
      tabCoordinator: _tabCoordinator,
      addressController: _addressController,
    );
  }

  bool _shouldPauseCurrentWebViewOnTabSwitch(String url) {
    return _statePredicates.shouldPauseCurrentWebViewOnTabSwitch(url);
  }

  BrowserPageTabTransitionDeps get _tabTransitionDeps {
    return BrowserPageTabTransitionDeps(
      pauseCurrentWebView: () {
        if (!_shouldPauseCurrentWebViewOnTabSwitch(_currentUrl)) {
          return;
        }
        final controller = _webViewController;
        if (controller == null) {
          return;
        }
        controller.pause();
        unawaited(
          controller.evaluateJavascript(
            source:
                BrowserPageWebViewLifecycleHelper.pauseVideoForOverlayScript,
          ),
        );
      },
      detachCurrentController: () {
        final currentTabId = _activeTabId;
        _webViewController = null;
        if (currentTabId != null) {
          _updateTabById(currentTabId, hasAttachedWebView: false);
        }
      },
      unfocusAddressBar: _addressFocusNode.unfocus,
      syncAddressBar: _syncAddressBarForCurrentTab,
      checkFavoriteStatus: _checkFavoriteStatus,
      resetProgress: _resetProgress,
      trimBackgroundKeepAlives: () {
        _tabCoordinator.trimInactiveKeepAlives(
          inactiveThreshold: Duration.zero,
          maxRetainedBackgroundTabs: 1,
        );
      },
    );
  }

  Future<void> _restoreSavedScrollPosition(
    InAppWebViewController controller,
    String tabId,
  ) async {
    final savedScroll = _tabCoordinator.tabById(tabId)?.scrollPosition ?? 0;
    if (savedScroll <= 0) {
      return;
    }

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_isActiveTabId(tabId)) {
        return;
      }
      await controller.scrollTo(x: 0, y: savedScroll.toInt(), animated: false);
    } catch (_) {}
  }

  Future<void> _showFavoritesHome({bool resetNavigationState = true}) async {
    _addressFocusNode.unfocus();
    _resetVideoDetectionState();
    _resetProgress();
    _favoritesCoordinator.applyFavoritesHomeState(
      tabCoordinator: _tabCoordinator,
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

  void _markTabWebViewAttached(String tabId) {
    final tab = _tabCoordinator.tabById(tabId);
    if (tab == null || tab.hasAttachedWebView) {
      return;
    }
    _updateTabById(tabId, hasAttachedWebView: true);
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
    _isLoadingNotifier.dispose();
    _canGoBackNotifier.dispose();
    _canGoForwardNotifier.dispose();
    _isSecureNotifier.dispose();
    _tabCountNotifier.dispose();
    _statusMessageNotifier.dispose();
    _overlayStateManager.dispose();
    _favoriteStatusController.dispose();
    unawaited(_videoPlayerCoordinator.dispose());
    _findController.dispose();
    _pullToRefreshController?.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    final hostedTabId = _activeTabId;
    final activeTab = _activeTab;
    final isFavoritesPage = _isFavoritesPage(_currentUrl);
    return BrowserPageBodySection(
      isFavoritesPage: isFavoritesPage,
      freezeWebViewForOverlay: _shouldFreezeWebViewForOverlay,
      // Only construct the favorites page widget when it's actually visible.
      // When the WebView is active, creating BrowserFavoritesPage is wasted
      // work that rebuilds a complex widget tree that won't even be rendered.
      favoritesChild: isFavoritesPage
          ? RepaintBoundary(
              child: BrowserFavoritesPage(
                key: _favoritesPageKey,
                onOpenUrl: (url) async {
                  await _loadAddress(url);
                },
              ),
            )
          : const SizedBox.shrink(),
      webViewChild: BrowserWebViewHost(
        key: ValueKey('webview-${_activeTabId ?? 'none'}'),
        enabled: widget.enableWebView,
        initialUrl: _currentUrl,
        shouldLoadInitialUrl: _statePredicates.shouldLoadInitialUrlForTab(
          activeTab,
        ),
        windowId: activeTab?.popupWindowId,
        keepAlive: activeTab?.keepAlive,
        isLoading: _isLoading,
        progressListenable: _progressNotifier,
        onWebViewCreated: (controller) {
          if (!_isActiveTabId(hostedTabId)) {
            return;
          }
          _webViewController = controller;
          if (hostedTabId != null) {
            _markTabWebViewAttached(hostedTabId);
            final adoptedPopupWindowId = _tabCoordinator
                .tabById(hostedTabId)
                ?.popupWindowId;
            if (adoptedPopupWindowId != null) {
              _updateTabById(hostedTabId, clearPopupWindowId: true);
            }
            unawaited(_restoreSavedScrollPosition(controller, hostedTabId));
          }
          if (_overlayStateManager.shouldResumeControllerOnAttach) {
            _resumeWebViewFromOverlay();
          } else {
            controller.resume();
          }
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
          _handleWebViewLoadStart(hostedTabId: hostedTabId, url: url);
        },
        onLoadStop: (controller, url) async {
          await _handleWebViewLoadStop(
            hostedTabId: hostedTabId,
            controller: controller,
            url: url,
          );
        },
        onProgressChanged: (controller, progress) {
          _handleWebViewProgressChanged(
            hostedTabId: hostedTabId,
            progress: progress,
          );
        },
        onReceivedError: (controller, request, error) {
          _handleWebViewReceivedError(
            hostedTabId: hostedTabId,
            request: request,
            error: error,
          );
        },
        onReceivedHttpAuthRequest: _handleHttpAuthRequest,
        onScrollChanged: (controller, x, y) {
          _handleWebViewScrollChanged(hostedTabId: hostedTabId, y: y);
        },
        onTitleChanged: (controller, title) {
          _handleWebViewTitleChanged(hostedTabId: hostedTabId, title: title);
        },
        onUpdateVisitedHistory: (controller, url, isReload) {
          _handleWebViewVisitedHistoryUpdate(
            hostedTabId: hostedTabId,
            controller: controller,
            url: url,
          );
        },
        pullToRefreshController: _pullToRefreshController,
        findInteractionController: _findController.interactionController,
      ),
      statusMessage: _statusMessageNotifier,
    );
  }

  Future<String?> _getInitialIntentUrl() async {
    return _externalIntentHelper.getInitialIntentUrl();
  }

  void _handleWebViewLoadStart({
    required String? hostedTabId,
    required WebUri? url,
  }) {
    if (hostedTabId == null) {
      return;
    }
    unawaited(_recordCookieOrigin(url));
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
      _setStateIfVisible(() {
        _statusMessage = _statusCoordinator.cleared();
      });
    }
    _syncUrlForTabIfNeeded(hostedTabId, url?.toString());
  }

  Future<void> _handleWebViewLoadStop({
    required String? hostedTabId,
    required InAppWebViewController controller,
    required WebUri? url,
  }) async {
    if (hostedTabId == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    _pullToRefreshController?.endRefreshing();
    unawaited(_recordCookieOrigin(url));
    unawaited(_injectSiteCompatibilityFixes(controller, url));
    final didChangeLoading = _updateTabById(hostedTabId, isLoading: false);
    final didChangeProgress = _isActiveTabId(hostedTabId)
        ? _updateProgressIfNeeded(100)
        : false;
    _syncUrlForTabIfNeeded(hostedTabId, url?.toString());

    final currentTitle = _tabCoordinator.tabById(hostedTabId)?.title ?? '';
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
      _setStateIfVisible(() {});
    }

    unawaited(
      _completeLoadStopFollowUp(
        hostedTabId: hostedTabId,
        controller: controller,
        url: url,
      ),
    );

    unawaited(_restoreSavedScrollPosition(controller, hostedTabId));
  }

  void _handleWebViewProgressChanged({
    required String? hostedTabId,
    required int progress,
  }) {
    if (_isActiveTabId(hostedTabId)) {
      _updateProgressIfNeeded(progress);
    }
  }

  void _handleWebViewReceivedError({
    required String? hostedTabId,
    required WebResourceRequest request,
    required WebResourceError error,
  }) {
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
    final decision = _webViewCoordinator.decideErrorStatus(
      description: error.description,
      blockedPopupStatus: _statusCoordinator.blockedPopup(),
      externalSchemeStatus: _statusCoordinator.externalAppContinuing(),
    );
    if (decision.action == BrowserPageWebViewErrorAction.blockedByResponse) {
      unawaited(_handleBlockedByResponse(request.url));
      _setStateIfVisible(() {
        _statusMessage = decision.statusMessage;
      });
      return;
    }
    if (decision.action == BrowserPageWebViewErrorAction.externalScheme) {
      final requestedUrl = request.url;
      if (!_isWebScheme(requestedUrl.scheme)) {
        unawaited(_confirmAndLaunchExternalUrl(requestedUrl));
      }
      _setStateIfVisible(() {
        _statusMessage = decision.statusMessage;
      });
      return;
    }
    _setStateIfVisible(() {
      _statusMessage = decision.statusMessage;
    });
  }

  void _handleWebViewScrollChanged({
    required String? hostedTabId,
    required int y,
  }) {
    if (hostedTabId == null) {
      return;
    }
    _updateScrollPositionForTabIfNeeded(hostedTabId, y.toDouble());
  }

  void _handleWebViewTitleChanged({
    required String? hostedTabId,
    required String? title,
  }) {
    if (hostedTabId == null) {
      return;
    }
    _updateTabById(hostedTabId, title: title ?? '');
  }

  void _handleWebViewVisitedHistoryUpdate({
    required String? hostedTabId,
    required InAppWebViewController controller,
    required WebUri? url,
  }) {
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
      unawaited(_recordCookieOrigin(url));
      unawaited(_handleVisitedHistoryUpdate(controller, url));
    } else if (url != null &&
        _webViewCoordinator.shouldSyncVisitedHistoryForBackgroundTab(
          isActiveTab: _isActiveTabId(hostedTabId),
          isFavoritesPage: _isFavoritesPage(currentTabUrl),
          isWebScheme: _isWebScheme(url.scheme),
        )) {
      _updateTabById(hostedTabId, url: url.toString());
    }
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

    await _favoriteStatusController.refreshStatus(
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
    final resolvedInput = _resolveInput(rawValue.trim());
    final plan = _addressBarCoordinator.buildLoadPlan(
      rawValue: rawValue,
      isProxyActive: _isProxyActive,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
      hasWebViewController: _webViewController != null,
      shouldOpenNativeVideo:
          resolvedInput.isNotEmpty &&
          _shouldOpenNativeVideoFromUrl(resolvedInput),
    );
    final target = plan.target;
    if (target == null) {
      return;
    }

    if (plan.shouldOpenNativeVideo) {
      await _handleExplicitYoutubeInput(target);
      return;
    }

    _addressController.text = target;
    final didChangeUrl = _updateActiveTab(
      url: target,
      isExternallyOpened: false,
    );
    final activeTabId = _activeTabId;
    if (activeTabId != null) {
      _tabService.ensureKeepAlive(activeTabId);
    }
    _checkFavoriteStatus(target);
    if (_statusCoordinator.shouldClearAfterAddressLoad(
      wasFavoritesPage: plan.wasFavoritesPage,
      didChangeUrl: didChangeUrl,
      currentStatusMessage: _statusMessage,
    )) {
      _setStateIfVisible(() {
        _statusMessage = _statusCoordinator.cleared();
      });
    }

    final controller = _webViewController;
    if (plan.shouldLoadInCurrentWebView && controller != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
      return;
    }

    if (plan.shouldRebuildAfterAddressLoad) {
      if (mounted) {
        _rebuildWhenVisible();
      }
      return;
    }

    if (plan.shouldResetKeepAliveAfterAddressLoad && activeTabId != null) {
      _tabService.resetKeepAlive(activeTabId, recreate: false);
      if (mounted) {
        _rebuildWhenVisible();
      }
    }
  }

  String _resolveInput(String input) {
    if (input.trim().isEmpty) {
      return '';
    }
    return BrowserPageInputResolver().resolve(
      input,
      isProxyActive: _isProxyActive,
    );
  }

  bool _shouldOpenNativeVideoFromUrl(String url) {
    return _statePredicates.shouldOpenNativeVideoFromUrl(
      videoPlayerCoordinator: _videoPlayerCoordinator,
      url: url,
      settings: _settings,
    );
  }

  Future<void> _handleExplicitYoutubeInput(String url) async {
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
  }

  bool _shouldUseProxy([BrowserSettings? settings, bool? proxySupported]) {
    final effectiveSettings = settings ?? _settings;
    final effectiveProxySupported = proxySupported ?? _proxySupported;
    return _statePredicates.shouldUseProxy(
      settings: effectiveSettings,
      proxySupported: effectiveProxySupported,
    );
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
    bool clearPopupWindowId = false,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
    bool? isExternallyOpened,
  }) {
    return _tabCoordinator.updateActiveTab(
      url: url,
      clearPopupWindowId: clearPopupWindowId,
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
    bool? hasAttachedWebView,
    bool clearPopupWindowId = false,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
  }) {
    return _tabCoordinator.updateTabById(
      tabId,
      url: url,
      hasAttachedWebView: hasAttachedWebView,
      clearPopupWindowId: clearPopupWindowId,
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
    if (result.didChangeUrl) {
      _updateTabById(tabId, clearPopupWindowId: true);
    }
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
    if (!mounted || !result.didChangeSecureState) {
      return;
    }
    _rebuildWhenVisible();
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
    _notifierSync.resetProgress(
      progressNotifier: _progressNotifier,
      setProgress: (value) {
        _progress = value;
      },
    );
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
    _rebuildWhenVisible();
  }

  Future<void> _completeLoadStopFollowUp({
    required String hostedTabId,
    required InAppWebViewController controller,
    required WebUri? url,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
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

    if (didChangeNavigation && _activeTabId == hostedTabId) {
      _setStateIfVisible(() {});
    }
  }

  Future<void> _injectSiteCompatibilityFixes(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    final script = BrowserSiteCompatibilityScript.bottomNavigationFixForUrl(
      url?.toString(),
    );
    if (script == null) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      // Best-effort compatibility CSS only. Navigation must not fail because a
      // site rejects script execution during early load transitions.
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
        await _openTab(
          initialUrl != null && initialUrl.isNotEmpty
              ? initialUrl
              : 'about:blank',
          statusMessage: _statusCoordinator.popupOpenedInNewTab(),
          popupWindowId: createWindowAction.windowId,
        );
        return true;
      case BrowserPopupWindowAction.showPopup:
        await _runTrackedOverlayAction(() async {
          await _popupWindowHandler.showPopupWindow(
            context: context,
            windowId: createWindowAction.windowId,
            initialUrl: decision.initialUrl,
            onStatus: (message) {
              _setStatusMessage(message);
            },
          );
        });
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
    _handleOverlayOpened();
    try {
      await _siteSecurityHelper.showSiteSecurityDialog(
        context: context,
        currentUrl: _currentUrl,
        isSecure: _isSecure,
        siteDataManager: _siteDataManager,
        onClearSiteData: _clearCurrentSiteData,
      );
    } finally {
      _handleOverlayClosed();
    }
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
    int? popupWindowId,
  }) async {
    final tab = _tabCoordinator.openTab(
      url: url,
      title: title,
      isExternallyOpened: isExternallyOpened,
      popupWindowId: popupWindowId,
    );
    if (!mounted) {
      return;
    }
    await _tabTransitionCoordinator.prepareOpenedTab(
      deps: _tabTransitionDeps,
      resetVideoDetectionState: _resetVideoDetectionState,
      url: tab.url,
      applyStatusAfterTransition: () {
        if (mounted) {
          _setStateIfVisible(() {
            _statusMessage = statusMessage;
          });
        }
      },
      syncTrackedScrollPosition:
          _tabCoordinator.syncTrackedScrollPositionWithActiveTab,
    );
  }

  void _setStatusMessage(String message) {
    if (!mounted || _statusMessage == message) {
      return;
    }
    _setStateIfVisible(() {
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
    await _tabTransitionCoordinator.prepareSwitchedTab(
      deps: _tabTransitionDeps,
      resetVideoDetectionState: _resetVideoDetectionState,
      url: _currentUrl,
      applyStatusAfterTransition: () {
        if (mounted) {
          _setStateIfVisible(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
      syncTrackedScrollPosition:
          _tabCoordinator.syncTrackedScrollPositionWithActiveTab,
    );
  }

  Future<void> _closeTab(String tabId) async {
    final previousActiveId = _activeTabId;
    final nextTab = _tabCoordinator.closeTab(tabId);
    if (!mounted) {
      return;
    }
    await _tabTransitionCoordinator.prepareClosedTab(
      deps: _tabTransitionDeps,
      url: nextTab.url,
      applyStatusAfterTransition: () {
        if (mounted) {
          _setStateIfVisible(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
    );

    final previousId = previousActiveId;
    if (previousId == null) {
      _rebuildWhenVisible();
      return;
    }
    final decision = _tabTransitionCoordinator.decideCloseTabFollowUp(
      previousActiveId: previousId,
      nextTabId: nextTab.id,
    );
    if (decision.followUp == BrowserPageCloseTabFollowUp.switchToTab) {
      await _switchToTab(decision.nextTabId);
      return;
    }
    _rebuildWhenVisible();
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
    await _tabTransitionCoordinator.prepareCloseAllTabs(
      deps: _tabTransitionDeps,
      url: _currentUrl,
      applyStatusAfterTransition: () {
        if (mounted) {
          _setStateIfVisible(() {
            _statusMessage = _statusCoordinator.cleared();
          });
        }
      },
    );
    unawaited(_tabService.saveSessions());
  }

  void _syncUrlIfNeeded(String? url) {
    final result = _tabCoordinator.syncActiveUrlIfNeeded(url);
    if (result.didChangeUrl) {
      _updateActiveTab(clearPopupWindowId: true);
    }
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
    if (!mounted || !result.didChangeSecureState) {
      return;
    }
    _rebuildWhenVisible();
  }

  void _handleFavoriteStatusChanged() {
    if (!mounted) {
      return;
    }
    _rebuildWhenVisible();
  }

  Future<void> _checkFavoriteStatus(String url) async {
    await _favoriteStatusController.checkStatus(
      url,
      isFavoritesPage: _isFavoritesPage(url),
    );
  }

  Future<void> _toggleFavorite() async {
    final url = _currentUrl;
    final title = _activeTab?.title ?? '';

    final result = await _favoriteStatusController.toggleFavorite(
      url: url,
      title: title,
      isFavoritesPage: _isFavoritesPage(url),
    );
    if (result == null || !mounted) {
      return;
    }
    _showSnackBar(result.message);
  }

  void _resetVideoDetectionState() {
    _videoDetectionCoordinator.resetAll();
    _tabCoordinator.resetTrackedScrollPosition();
  }

  bool _isWebScheme(String? scheme) {
    return _urlFilterHelper.isWebScheme(scheme);
  }

  bool _shouldSuppressPopupUrl(String? url) {
    return _urlFilterHelper.shouldSuppressPopupUrl(url);
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

    await _runTrackedOverlayAction(() async {
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
    });
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
    await _modalCoordinator.showTabSwitcher(
      overlayStateManager: _overlayStateManager,
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
    await _modalCoordinator.showMoreActions(
      overlayStateManager: _overlayStateManager,
      context: context,
      proxyEnabled: _settings.shouldApplyProxy,
      isFavorited: _favoriteStatusController.isCurrentPageFavorited,
      onToggleFavorite: _isFavoritesPage(_currentUrl) ? null : _toggleFavorite,
      onToggleProxy: _toggleProxy,
      onOpenDownloads: _openDownloads,
      onOpenDataManagement: _openDataManagement,
      onCloseTab: _closeCurrentTab,
      onOpenSettings: _openSettings,
      onEnterFloatingWindowMode: _enterFloatingButtonMode,
      onExitApp: () async {
        await AppLifecycleManager().shutdownAllServices();
        await SystemNavigator.pop();
      },
      onOpenFavoritesMenu: _isFavoritesPage(_currentUrl)
          ? _showFavoritesMenu
          : null,
      onFindInPage: () {
        _overlayStateManager.markShowFindInPageAfterMoreActionsCloses();
      },
    );

    if (_overlayStateManager.shouldShowFindInPageAfterMoreActionsCloses) {
      _overlayStateManager.clearShowFindInPageAfterMoreActionsCloses();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) {
        await _showFindInPage();
      }
    }
  }

  Future<void> _enterFloatingButtonMode() async {
    final result = await _proxyService.startFloatingButtonMode();
    if (!mounted) {
      return;
    }

    switch (result) {
      case 'started':
        _statusMessage = '已缩为悬浮按钮，可在其他应用继续使用代理';
        break;
      case 'permission_required':
        _showSnackBar('请授予悬浮窗权限后重试');
        break;
      default:
        _showSnackBar('启动悬浮按钮失败');
        break;
    }
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
          _rebuildWhenVisible();
        }
      },
    );
  }

  Future<void> _showFavoritesMenu() async {
    final favoritesState = _favoritesPageKey.currentState;
    if (favoritesState == null) {
      return;
    }

    await _modalCoordinator.showFavoritesMenu(
      overlayStateManager: _overlayStateManager,
      context: context,
      onAddFavorite: favoritesState.showAddFavoriteDialog,
      onToggleReorderMode: favoritesState.toggleReorderMode,
    );
  }

  Future<void> _showFindInPage() async {
    if (_isFavoritesPage(_currentUrl)) {
      await _loadAddress(_settings.homepageUrl);
      if (!mounted) {
        return;
      }
      _rebuildWhenVisible();
      if (!mounted) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _isFavoritesPage(_currentUrl)) {
        return;
      }
    }

    if (!_actionCoordinator.canShowFindInPage(
      isFindAvailable: _findController.isAvailable,
      isFavoritesPage: _isFavoritesPage(_currentUrl),
    )) {
      return;
    }

    await _modalCoordinator.showFindInPage(
      overlayStateManager: _overlayStateManager,
      context: context,
      findController: _findController,
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    unawaited(AppToast.show(message));
  }

  Future<void> _recordHistory(WebUri? url, String title) async {
    await _historyRecorder.recordHistory(url, title);
  }

  Future<void> _recordCookieOrigin(WebUri? url) async {
    await _cookieOriginService.recordUrl(url?.toString());
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
        drawer: AppDrawer(onOpenSettings: _openSettings),
        onDrawerChanged: (isOpened) {
          if (isOpened) {
            _handleOverlayOpened();
          } else {
            _handleOverlayClosed();
          }
        },
        appBar: BrowserPageAppBar(
          addressController: _addressController,
          addressFocusNode: _addressFocusNode,
          isSecure: _isSecureNotifier,
          suggestionService: _suggestionService,
          onSecurityPressed: _showSiteSecurityDialog,
          onClear: _addressController.clear,
          currentUrl: _currentUrl,
          onSubmitted: (value) async {
            await _loadAddress(value);
            _addressFocusNode.unfocus();
          },
          isLoading: _isLoadingNotifier,
          onRefresh: () async {
            if (_isLoading) {
              await _webViewController?.stopLoading();
              _updateActiveTab(isLoading: false);
              if (mounted) {
                _rebuildWhenVisible();
              }
              return;
            }
            await _webViewController?.reload();
          },
        ),
        body: RepaintBoundary(
          child: !_isInitialized
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
        ),
        bottomNavigationBar: RepaintBoundary(
          child: BrowserPageBottomBar(
            canGoBack: _canGoBackNotifier,
            canGoForward: _canGoForwardNotifier,
            isLoading: _isLoadingNotifier,
            tabCount: _tabCountNotifier,
            proxyEnabled: _settings.shouldApplyProxy,
            onBack: _handleBrowserBack,
            onForward: () async => _webViewController?.goForward(),
            onHome: _showFavoritesHome,
            onOpenTabs: _showTabSwitcher,
            onOpenMoreActions: _showMoreActions,
            onFindInPage: _showFindInPage,
          ),
        ),
      ),
    );
  }
}
