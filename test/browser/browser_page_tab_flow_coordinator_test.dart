import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_tab_flow_coordinator.dart';

void main() {
  group('BrowserPageTabFlowCoordinator', () {
    const coordinator = BrowserPageTabFlowCoordinator();

    test(
      'back action priority follows overlay fullscreen webview tabs favorites exit',
      () {
        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: true,
                isVideoFullscreen: true,
                isInWebFullscreen: true,
                canGoBackInWebView: true,
                tabCount: 3,
                activeTabId: 'a',
                isFavoritesPage: false,
              )
              .action,
          BrowserPageBackAction.exitVideoFullscreen,
        );

        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: true,
                isVideoFullscreen: false,
                isInWebFullscreen: true,
                canGoBackInWebView: true,
                tabCount: 3,
                activeTabId: 'a',
                isFavoritesPage: false,
              )
              .action,
          BrowserPageBackAction.closeVideoOverlay,
        );

        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: false,
                isVideoFullscreen: false,
                isInWebFullscreen: true,
                canGoBackInWebView: true,
                tabCount: 3,
                activeTabId: 'a',
                isFavoritesPage: false,
              )
              .action,
          BrowserPageBackAction.exitWebFullscreen,
        );

        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: false,
                isVideoFullscreen: false,
                isInWebFullscreen: false,
                canGoBackInWebView: true,
                tabCount: 3,
                activeTabId: 'a',
                isFavoritesPage: false,
              )
              .action,
          BrowserPageBackAction.goBackInWebView,
        );

        final closeDecision = coordinator.decideBackAction(
          hasActiveVideoOverlay: false,
          isVideoFullscreen: false,
          isInWebFullscreen: false,
          canGoBackInWebView: false,
          tabCount: 2,
          activeTabId: 'a',
          isFavoritesPage: false,
        );
        expect(closeDecision.action, BrowserPageBackAction.closeActiveTab);
        expect(closeDecision.activeTabId, 'a');

        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: false,
                isVideoFullscreen: false,
                isInWebFullscreen: false,
                canGoBackInWebView: false,
                tabCount: 1,
                activeTabId: 'a',
                isFavoritesPage: false,
              )
              .action,
          BrowserPageBackAction.showFavoritesHome,
        );

        expect(
          coordinator
              .decideBackAction(
                hasActiveVideoOverlay: false,
                isVideoFullscreen: false,
                isInWebFullscreen: false,
                canGoBackInWebView: false,
                tabCount: 1,
                activeTabId: 'a',
                isFavoritesPage: true,
              )
              .action,
          BrowserPageBackAction.exitApp,
        );
      },
    );

    test('close tab follow up chooses switch or rebuild', () {
      expect(
        coordinator
            .decideCloseTabFollowUp(previousActiveId: 'a', nextTabId: 'b')
            .followUp,
        BrowserPageCloseTabFollowUp.switchToTab,
      );
      expect(
        coordinator
            .decideCloseTabFollowUp(previousActiveId: 'a', nextTabId: 'a')
            .followUp,
        BrowserPageCloseTabFollowUp.rebuild,
      );
    });

    test('favorites page uses favorites host instead of webview load', () {
      expect(
        coordinator.shouldShowFavoritesInsteadOfLoading(isFavoritesPage: true),
        isTrue,
      );
      expect(
        coordinator.shouldShowFavoritesInsteadOfLoading(isFavoritesPage: false),
        isFalse,
      );
    });
  });
}
