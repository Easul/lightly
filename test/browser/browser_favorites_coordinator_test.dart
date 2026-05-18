import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_favorites_coordinator.dart';
import 'package:lightly/browser/services/browser_tab_coordinator.dart';
import 'package:lightly/browser/services/browser_tab_service.dart';

void main() {
  group('BrowserFavoritesCoordinator', () {
    late BrowserTabService tabService;
    late BrowserTabCoordinator tabCoordinator;
    const favoritesCoordinator = BrowserFavoritesCoordinator();

    setUp(() {
      tabService = BrowserTabService();
      _resetTabService(tabService);
      tabCoordinator = BrowserTabCoordinator(
        tabService: tabService,
        favoritesPageUrl: favoritesCoordinator.favoritesPageUrl,
      );
    });

    test('identifies the favorites pseudo-url', () {
      expect(
        favoritesCoordinator.isFavoritesPage('ruoqing://favorites'),
        isTrue,
      );
      expect(
        favoritesCoordinator.isFavoritesPage('https://example.com'),
        isFalse,
      );
    });

    test('applies favorites-home state to the active tab', () {
      final tab = tabCoordinator.openTab(
        url: 'https://example.com',
        title: 'Example',
      );
      tabCoordinator.activateTab(tab.id);
      tabCoordinator.updateActiveTab(
        isLoading: true,
        canGoBack: true,
        canGoForward: true,
        scrollPosition: 120,
      );

      favoritesCoordinator.applyFavoritesHomeState(
        tabCoordinator: tabCoordinator,
      );

      expect(tabCoordinator.currentUrl, favoritesCoordinator.favoritesPageUrl);
      expect(tabCoordinator.activeTab?.title, '');
      expect(tabCoordinator.isLoading, isFalse);
      expect(tabCoordinator.canGoBack, isFalse);
      expect(tabCoordinator.canGoForward, isFalse);
      expect(tabCoordinator.activeTab?.scrollPosition, 0);
      expect(tabCoordinator.activeTab?.keepAlive, isNotNull);
    });
  });
}

void _resetTabService(BrowserTabService service) {
  service.setFallbackUrl('ruoqing://favorites');
  for (final tab in List.of(service.tabs)) {
    service.closeTab(tab.id);
  }
  final activeTab = service.activeTab;
  if (activeTab == null) {
    service.initialize('ruoqing://favorites');
    return;
  }
  service.updateTab(
    activeTab.id,
    url: 'ruoqing://favorites',
    title: '',
    isLoading: false,
    canGoBack: false,
    canGoForward: false,
    scrollPosition: 0,
  );
}
