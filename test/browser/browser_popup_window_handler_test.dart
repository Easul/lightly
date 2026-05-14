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
    });

    test('keeps trusted auth popups as popup dialogs', () {
      final decision = handler.decide(
        requestedUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
        sourceUrl: 'https://example.com/login',
        hasGesture: true,
        openNewWindowInTab: true,
      );

      expect(decision.action, BrowserPopupWindowAction.showPopup);
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

    test('allows deferred auth popups with empty url', () {
      final decision = handler.decide(
        requestedUrl: '',
        sourceUrl: 'https://example.com/oauth/login',
        hasGesture: true,
        openNewWindowInTab: false,
      );

      expect(decision.action, BrowserPopupWindowAction.showPopup);
      expect(decision.initialUrl, isNull);
      expect(decision.statusMessage, '站点正在延迟创建登录窗口，已改为弹窗继续');
    });
  });
}
