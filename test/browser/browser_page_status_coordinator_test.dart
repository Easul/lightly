import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_status_coordinator.dart';

void main() {
  group('BrowserPageStatusCoordinator', () {
    const coordinator = BrowserPageStatusCoordinator();

    test('returns stable page status strings', () {
      expect(coordinator.cleared(), '');
      expect(coordinator.youtubeResolving(), '正在解析 YouTube 视频');
      expect(coordinator.blockedPopup(), '网页拦截了当前弹窗/跳转，请确认是否外部打开');
      expect(coordinator.externalAppContinuing(), '检测到外部应用跳转，正在尝试继续');
    });

    test('clears status when favorites, url change, or message exists', () {
      expect(
        coordinator.shouldClearAfterAddressLoad(
          wasFavoritesPage: true,
          didChangeUrl: false,
          currentStatusMessage: '',
        ),
        isTrue,
      );
      expect(
        coordinator.shouldClearAfterAddressLoad(
          wasFavoritesPage: false,
          didChangeUrl: true,
          currentStatusMessage: '',
        ),
        isTrue,
      );
      expect(
        coordinator.shouldClearAfterAddressLoad(
          wasFavoritesPage: false,
          didChangeUrl: false,
          currentStatusMessage: 'msg',
        ),
        isTrue,
      );
      expect(
        coordinator.shouldClearAfterAddressLoad(
          wasFavoritesPage: false,
          didChangeUrl: false,
          currentStatusMessage: '',
        ),
        isFalse,
      );
    });

    test('shows youtube resolving only when status differs', () {
      expect(coordinator.shouldShowYoutubeResolving(''), isTrue);
      expect(
        coordinator.shouldShowYoutubeResolving(coordinator.youtubeResolving()),
        isFalse,
      );
    });

    test('external status falls back to current status when null', () {
      expect(
        coordinator.nextExternalStatus(
          externalStatusMessage: null,
          currentStatusMessage: 'keep',
        ),
        'keep',
      );
      expect(
        coordinator.nextExternalStatus(
          externalStatusMessage: 'next',
          currentStatusMessage: 'keep',
        ),
        'next',
      );
    });
  });
}
