import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_status_coordinator.dart';

void main() {
  group('BrowserPageStatusCoordinator', () {
    const coordinator = BrowserPageStatusCoordinator();

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
