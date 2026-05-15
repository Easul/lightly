import 'package:flutter_test/flutter_test.dart';
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
  });
}
