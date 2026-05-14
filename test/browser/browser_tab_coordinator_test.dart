import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_tab_coordinator.dart';
import 'package:lightly/browser/services/browser_tab_service.dart';

void main() {
  group('BrowserTabCoordinator', () {
    late BrowserTabService tabService;
    late BrowserTabCoordinator coordinator;

    setUp(() {
      tabService = BrowserTabService();
      _resetTabService(tabService);
      coordinator = BrowserTabCoordinator(
        tabService: tabService,
        favoritesPageUrl: 'ruoqing://favorites',
      );
    });

    test('returns empty address bar text for favorites page', () {
      expect(coordinator.currentUrl, 'ruoqing://favorites');
      expect(coordinator.addressBarTextForCurrentTab(), '');
    });

    test('does not overwrite favorites tab with a web url during sync', () {
      final result = coordinator.syncUrlForTabIfNeeded(
        coordinator.activeTabId!,
        'https://example.com',
      );

      expect(result.didChangeUrl, isFalse);
      expect(coordinator.currentUrl, 'ruoqing://favorites');
      expect(tabService.activeTab?.url, 'ruoqing://favorites');
    });

    test('syncs active url and reports secure-state changes', () {
      final firstTab = coordinator.openTab(url: 'http://example.com');
      coordinator.activateTab(firstTab.id);

      final result = coordinator.syncActiveUrlIfNeeded(
        'https://secure.example',
      );

      expect(result.didChangeUrl, isTrue);
      expect(result.didChangeSecureState, isTrue);
      expect(coordinator.currentUrl, 'https://secure.example');
      expect(coordinator.isSecure, isTrue);
    });

    test('tracks significant scroll changes only for active tab', () {
      final firstTab = coordinator.openTab(url: 'https://example.com');
      coordinator.activateTab(firstTab.id);
      coordinator.syncTrackedScrollPositionWithActiveTab();

      final smallChange = coordinator.updateScrollPositionForTabIfNeeded(
        firstTab.id,
        10,
      );
      final largeChange = coordinator.updateScrollPositionForTabIfNeeded(
        firstTab.id,
        32,
      );

      expect(smallChange.didUpdate, isFalse);
      expect(largeChange.didUpdate, isTrue);
      expect(largeChange.updatedActiveTab, isTrue);
      expect(tabService.activeTab?.scrollPosition, 32);
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
