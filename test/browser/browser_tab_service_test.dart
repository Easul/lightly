import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lightly/browser/services/browser_tab_service.dart';

void main() {
  group('BrowserTabService', () {
    test('initializes with a single active tab', () {
      final service = BrowserTabService();

      service.initialize('https://www.google.com');

      expect(service.tabCount, 1);
      expect(service.activeTab?.url, 'https://www.google.com');
    });

    test('switches and closes tabs while keeping an active session', () {
      final service = BrowserTabService();
      service.initialize('https://one.example');

      final second = service.openTab(url: 'https://two.example');
      service.openTab(url: 'https://three.example');

      final didSwitch = service.activateTab(second.id);
      final activeAfterClose = service.closeTab(second.id);

      expect(didSwitch, isTrue);
      expect(activeAfterClose.id, isNot(second.id));
      expect(service.activeTab?.id, activeAfterClose.id);
      expect(service.tabCount, 2);
    });

    test('evicts least recently used tab when max tab count is exceeded', () {
      final service = BrowserTabService.test(maxTabs: 3);
      service.initialize('https://one.example');
      final second = service.openTab(url: 'https://two.example');
      service.openTab(url: 'https://three.example');

      service.activateTab(second.id);
      service.openTab(url: 'https://four.example');

      final urls = service.tabs.map((tab) => tab.url).toList();
      expect(urls, isNot(contains('https://one.example')));
      expect(
        urls,
        containsAll(<String>[
          'https://two.example',
          'https://three.example',
          'https://four.example',
        ]),
      );
      expect(service.activeTab?.url, 'https://four.example');
    });

    test('does not persist externally opened tabs', () async {
      final service = BrowserTabService.test(maxTabs: 3);
      service.initialize('https://one.example');

      service.openTab(
        url: 'content://provider/document/file.txt',
        isExternallyOpened: true,
      );

      expect(service.activeTab?.isExternallyOpened, isTrue);
    });

    test('trims keepAlive objects for inactive background tabs', () {
      final service = BrowserTabService.test(maxTabs: 4);
      service.initialize('https://one.example');
      final second = service.openTab(url: 'https://two.example');
      service.openTab(url: 'https://three.example');

      service.activateTab(second.id);
      final trimmed = service.trimInactiveKeepAlives(
        inactiveThreshold: Duration.zero,
        maxRetainedBackgroundTabs: 0,
      );

      expect(trimmed, 2);
      expect(service.activeTab?.keepAlive, isNotNull);
      expect(
        service.tabs
            .where((tab) => tab.id != service.activeTab?.id)
            .every((tab) => tab.keepAlive == null),
        isTrue,
      );
    });

    test('restored sessions only keep the active tab alive', () async {
      SharedPreferences.setMockInitialValues({
        'browser_tab_sessions_v1':
            '{"tabs":[{"url":"https://one.example","title":"One"},{"url":"https://two.example","title":"Two"}],"activeIndex":1}',
      });
      final service = BrowserTabService.test(maxTabs: 4);

      await service.restoreSessions('https://fallback.example');

      expect(service.activeTab?.url, 'https://two.example');
      expect(service.activeTab?.keepAlive, isNotNull);
      final backgroundTabs = service.tabs
          .where((tab) => tab.id != service.activeTab?.id)
          .toList(growable: false);
      expect(backgroundTabs, hasLength(1));
      expect(backgroundTabs.single.keepAlive, isNull);
    });

    test('switching tabs keeps recently opened web tabs alive by default', () {
      final service = BrowserTabService.test(maxTabs: 4);
      service.initialize('https://one.example');
      final second = service.openTab(url: 'https://two.example');

      final firstTabBeforeSwitch = service.tabs.firstWhere(
        (tab) => tab.url == 'https://one.example',
      );
      expect(firstTabBeforeSwitch.keepAlive, isNotNull);

      service.activateTab(second.id);

      final firstTabAfterSwitch = service.tabs.firstWhere(
        (tab) => tab.url == 'https://one.example',
      );
      final secondTabAfterSwitch = service.tabs.firstWhere(
        (tab) => tab.id == second.id,
      );
      expect(firstTabAfterSwitch.keepAlive, isNotNull);
      expect(secondTabAfterSwitch.keepAlive, isNotNull);
    });

    test('overlay trimming retains two recent background tabs', () {
      final service = BrowserTabService.test(maxTabs: 5);
      service.initialize('https://one.example');
      final second = service.openTab(url: 'https://two.example');
      final third = service.openTab(url: 'https://three.example');
      final fourth = service.openTab(url: 'https://four.example');

      service.activateTab(second.id);
      service.activateTab(third.id);
      service.activateTab(fourth.id);

      final trimmed = service.trimKeepAlivesForOverlay();

      expect(trimmed, 1);
      final firstTab = service.tabs.firstWhere(
        (tab) => tab.url == 'https://one.example',
      );
      final secondTab = service.tabs.firstWhere(
        (tab) => tab.url == 'https://two.example',
      );
      final thirdTab = service.tabs.firstWhere(
        (tab) => tab.url == 'https://three.example',
      );
      final fourthTab = service.tabs.firstWhere(
        (tab) => tab.url == 'https://four.example',
      );

      expect(firstTab.keepAlive, isNull);
      expect(secondTab.keepAlive, isNotNull);
      expect(thirdTab.keepAlive, isNotNull);
      expect(fourthTab.keepAlive, isNotNull);
    });
  });
}
