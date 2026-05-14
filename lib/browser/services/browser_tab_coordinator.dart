import '../models/browser_tab_session.dart';
import '../utils/ui_update_thresholds.dart';
import 'browser_tab_service.dart';

class BrowserTabUrlSyncResult {
  const BrowserTabUrlSyncResult({
    required this.didChangeUrl,
    required this.isActiveTab,
    required this.previousUrl,
    required this.currentUrl,
    required this.didChangeSecureState,
  });

  final bool didChangeUrl;
  final bool isActiveTab;
  final String? previousUrl;
  final String? currentUrl;
  final bool didChangeSecureState;
}

class BrowserTabScrollSyncResult {
  const BrowserTabScrollSyncResult({
    required this.didUpdate,
    required this.updatedActiveTab,
  });

  final bool didUpdate;
  final bool updatedActiveTab;
}

class BrowserTabCoordinator {
  BrowserTabCoordinator({
    required BrowserTabService tabService,
    required String favoritesPageUrl,
  }) : _tabService = tabService,
       _favoritesPageUrl = favoritesPageUrl;

  final BrowserTabService _tabService;
  final String _favoritesPageUrl;

  double _lastReportedScrollPosition = 0;

  BrowserTabSession? get activeTab => _tabService.activeTab;
  String? get activeTabId => activeTab?.id;
  List<BrowserTabSession> get tabs => _tabService.tabs;
  String get currentUrl => activeTab?.url ?? _favoritesPageUrl;
  bool get isLoading => activeTab?.isLoading ?? false;
  bool get canGoBack =>
      (activeTab?.canGoBack ?? false) || !isFavoritesPage(currentUrl);
  bool get canGoForward => activeTab?.canGoForward ?? false;
  bool get isSecure =>
      !isFavoritesPage(currentUrl) && currentUrl.startsWith('https://');

  bool isFavoritesPage(String? url) => url == _favoritesPageUrl;

  BrowserTabSession? tabById(String tabId) => _tabService.tabById(tabId);

  String addressBarTextForCurrentTab() {
    return isFavoritesPage(currentUrl) ? '' : currentUrl;
  }

  bool updateActiveTab({
    String? url,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
  }) {
    final tabId = activeTabId;
    if (tabId == null) {
      return false;
    }

    return updateTabById(
      tabId,
      url: url,
      title: title,
      isLoading: isLoading,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      scrollPosition: scrollPosition,
    );
  }

  bool updateTabById(
    String tabId, {
    String? url,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
  }) {
    return _tabService.updateTab(
      tabId,
      url: url,
      title: title,
      isLoading: isLoading,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      scrollPosition: scrollPosition,
    );
  }

  bool isActiveTabId(String? tabId) => tabId != null && activeTabId == tabId;

  BrowserTabUrlSyncResult syncUrlForTabIfNeeded(String tabId, String? url) {
    if (url == null) {
      return const BrowserTabUrlSyncResult(
        didChangeUrl: false,
        isActiveTab: false,
        previousUrl: null,
        currentUrl: null,
        didChangeSecureState: false,
      );
    }

    final tab = _tabService.tabById(tabId);
    final previousUrl = tab?.url;
    final isWebUrl = _isWebScheme(Uri.tryParse(url)?.scheme);
    if (previousUrl != null && isFavoritesPage(previousUrl) && isWebUrl) {
      return BrowserTabUrlSyncResult(
        didChangeUrl: false,
        isActiveTab: isActiveTabId(tabId),
        previousUrl: previousUrl,
        currentUrl: previousUrl,
        didChangeSecureState: false,
      );
    }

    final didChangeUrl = previousUrl != url && updateTabById(tabId, url: url);
    final previousIsSecure =
        previousUrl != null &&
        !isFavoritesPage(previousUrl) &&
        previousUrl.startsWith('https://');
    final nextIsSecure = !isFavoritesPage(url) && url.startsWith('https://');
    return BrowserTabUrlSyncResult(
      didChangeUrl: didChangeUrl,
      isActiveTab: isActiveTabId(tabId),
      previousUrl: previousUrl,
      currentUrl: didChangeUrl ? url : previousUrl,
      didChangeSecureState: previousIsSecure != nextIsSecure,
    );
  }

  BrowserTabUrlSyncResult syncActiveUrlIfNeeded(String? url) {
    if (url == null) {
      return const BrowserTabUrlSyncResult(
        didChangeUrl: false,
        isActiveTab: false,
        previousUrl: null,
        currentUrl: null,
        didChangeSecureState: false,
      );
    }

    final previousUrl = currentUrl;
    final previousIsSecure = isSecure;
    final didChangeUrl = previousUrl != url && updateActiveTab(url: url);
    final nextIsSecure = url.startsWith('https://');
    return BrowserTabUrlSyncResult(
      didChangeUrl: didChangeUrl,
      isActiveTab: true,
      previousUrl: previousUrl,
      currentUrl: didChangeUrl ? url : previousUrl,
      didChangeSecureState: previousIsSecure != nextIsSecure,
    );
  }

  bool updateProgressIfNeeded(int currentProgress, int nextProgress) {
    return shouldUpdateWebProgress(currentProgress, nextProgress);
  }

  void resetTrackedScrollPosition() {
    _lastReportedScrollPosition = 0;
  }

  void syncTrackedScrollPositionWithActiveTab() {
    _lastReportedScrollPosition = activeTab?.scrollPosition ?? 0;
  }

  bool updateActiveScrollPositionIfNeeded(double scrollPosition) {
    if (!hasSignificantScrollChange(
      _lastReportedScrollPosition,
      scrollPosition,
    )) {
      return false;
    }

    _lastReportedScrollPosition = scrollPosition;
    return updateActiveTab(scrollPosition: scrollPosition);
  }

  BrowserTabScrollSyncResult updateScrollPositionForTabIfNeeded(
    String tabId,
    double scrollPosition,
  ) {
    final tab = _tabService.tabById(tabId);
    if (tab == null ||
        !hasSignificantScrollChange(tab.scrollPosition, scrollPosition)) {
      return const BrowserTabScrollSyncResult(
        didUpdate: false,
        updatedActiveTab: false,
      );
    }

    final didUpdate = updateTabById(tabId, scrollPosition: scrollPosition);
    final updatedActiveTab = didUpdate && activeTabId == tabId;
    if (updatedActiveTab) {
      _lastReportedScrollPosition = scrollPosition;
    }
    return BrowserTabScrollSyncResult(
      didUpdate: didUpdate,
      updatedActiveTab: updatedActiveTab,
    );
  }

  BrowserTabSession openTab({required String url, String title = ''}) {
    return _tabService.openTab(url: url, title: title);
  }

  bool activateTab(String tabId) => _tabService.activateTab(tabId);

  BrowserTabSession closeTab(String tabId) => _tabService.closeTab(tabId);

  void closeAllTabs() {
    for (final tab in List<BrowserTabSession>.from(tabs)) {
      _tabService.closeTab(tab.id);
    }
  }

  bool _isWebScheme(String? scheme) {
    if (scheme == null) {
      return false;
    }
    final normalized = scheme.toLowerCase();
    return normalized == 'http' || normalized == 'https';
  }
}
