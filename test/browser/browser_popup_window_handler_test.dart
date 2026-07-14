import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_popup_window_handler.dart';

void main() {
  group('BrowserPopupWindowHandler', () {
    late BrowserPopupWindowHandler handler;

    setUp(() {
      handler = BrowserPopupWindowHandler();
    });

    test('routes non-web popup urls to external handling', () {
      final decision = handler.decide(
        requestedUrl: 'blob:https://example.com/abc',
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: true,
      );

      expect(decision.action, BrowserPopupWindowAction.external);
      expect(decision.initialUrl, 'blob:https://example.com/abc');
      expect(decision.externalUrl, 'blob:https://example.com/abc');
    });

    test('decodes encoded app popup url before external handling', () {
      final decision = handler.decide(
        requestedUrl:
            'baiduboxapp%3A%2F%2Fv1%2Feasy%2Fbydird%3Fupgrade%3D1%26type%3Dhybird',
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: false,
      );

      expect(decision.action, BrowserPopupWindowAction.external);
      expect(
        decision.initialUrl,
        'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird',
      );
      expect(
        decision.externalUrl,
        'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird',
      );
    });

    test('keeps encoded bank payload intact for external launch', () {
      const encodedUrl =
          'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22type%22%3A%221%22%2C%22trafficTag%22%3A%2290fc%22%7D';
      final decision = handler.decide(
        requestedUrl: encodedUrl,
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: false,
      );

      expect(decision.action, BrowserPopupWindowAction.external);
      expect(
        decision.initialUrl,
        'bankabc://{"method":"jumpToSharedProduct","type":"1","trafficTag":"90fc"}',
      );
      expect(decision.externalUrl, encodedUrl);
    });

    test('routes trusted auth popups to new tabs', () {
      final decision = handler.decide(
        requestedUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
        sourceUrl: 'https://example.com/login',
        hasGesture: true,
        openNewWindowInTab: true,
      );

      expect(decision.action, BrowserPopupWindowAction.openTab);
      expect(
        decision.initialUrl,
        'https://accounts.google.com/o/oauth2/v2/auth',
      );
    });

    test('routes non-auth web popups to tab when setting enabled', () {
      final decision = handler.decide(
        requestedUrl: 'https://example.com/popup',
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: true,
      );

      expect(decision.action, BrowserPopupWindowAction.openTab);
      expect(decision.initialUrl, 'https://example.com/popup');
    });

    test('routes deferred auth popups with empty url to new tab flow', () {
      final decision = handler.decide(
        requestedUrl: '',
        sourceUrl: 'https://example.com/oauth/login',
        hasGesture: true,
        openNewWindowInTab: false,
      );

      expect(decision.action, BrowserPopupWindowAction.openTab);
      expect(decision.initialUrl, isNull);
      expect(decision.statusMessage, '站点正在延迟创建登录窗口，已改为新标签页继续');
    });

    test('routes empty gesture popup to new tab when enabled', () {
      final decision = handler.decide(
        requestedUrl: '',
        sourceUrl: 'https://example.com',
        hasGesture: true,
        openNewWindowInTab: true,
      );

      expect(decision.action, BrowserPopupWindowAction.openTab);
      expect(decision.initialUrl, isNull);
    });
  });
}
