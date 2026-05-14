import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_webview_coordinator.dart';

void main() {
  group('BrowserPageWebViewCoordinator', () {
    const coordinator = BrowserPageWebViewCoordinator();

    test('clears status on load start only for active tabs with changes', () {
      expect(
        coordinator.shouldClearStatusOnLoadStart(
          isActiveTab: true,
          currentStatusMessage: 'msg',
          didChangeProgress: false,
          didChangeLoading: false,
        ),
        isTrue,
      );
      expect(
        coordinator.shouldClearStatusOnLoadStart(
          isActiveTab: false,
          currentStatusMessage: 'msg',
          didChangeProgress: true,
          didChangeLoading: true,
        ),
        isFalse,
      );
    });

    test('rebuild decisions only trigger for active tab changes', () {
      expect(
        coordinator.shouldRebuildOnLoadStop(
          isActiveTab: true,
          didChangeProgress: true,
          didChangeTitle: false,
          didChangeLoading: false,
        ),
        isTrue,
      );
      expect(
        coordinator.shouldRebuildOnLoadStop(
          isActiveTab: false,
          didChangeProgress: true,
          didChangeTitle: true,
          didChangeLoading: true,
        ),
        isFalse,
      );
      expect(
        coordinator.shouldRebuildOnTitleChanged(
          isActiveTab: true,
          didChangeTitle: true,
        ),
        isTrue,
      );
    });

    test(
      'error decision distinguishes blocked response and external scheme',
      () {
        expect(
          coordinator
              .decideErrorStatus(
                description: 'net::ERR_BLOCKED_BY_RESPONSE',
                blockedPopupStatus: 'blocked',
                externalSchemeStatus: 'external',
              )
              .action,
          BrowserPageWebViewErrorAction.blockedByResponse,
        );
        expect(
          coordinator
              .decideErrorStatus(
                description: 'net::ERR_UNKNOWN_URL_SCHEME',
                blockedPopupStatus: 'blocked',
                externalSchemeStatus: 'external',
              )
              .action,
          BrowserPageWebViewErrorAction.externalScheme,
        );
        expect(
          coordinator
              .decideErrorStatus(
                description: 'plain error',
                blockedPopupStatus: 'blocked',
                externalSchemeStatus: 'external',
              )
              .statusMessage,
          'plain error',
        );
      },
    );

    test(
      'visited history routing distinguishes active and background tabs',
      () {
        expect(
          coordinator.shouldHandleVisitedHistoryForActiveTab(isActiveTab: true),
          isTrue,
        );
        expect(
          coordinator.shouldSyncVisitedHistoryForBackgroundTab(
            isActiveTab: false,
            isFavoritesPage: false,
            isWebScheme: true,
          ),
          isTrue,
        );
        expect(
          coordinator.shouldSyncVisitedHistoryForBackgroundTab(
            isActiveTab: true,
            isFavoritesPage: false,
            isWebScheme: true,
          ),
          isFalse,
        );
      },
    );
  });
}
