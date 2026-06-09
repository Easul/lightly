import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_tab_flow_coordinator.dart';
import 'package:lightly/pages/browser_page_tab_transition_coordinator.dart';
import 'package:lightly/pages/browser_page_tab_transition_helper.dart';

void main() {
  group('BrowserPageTabTransitionCoordinator', () {
    const coordinator = BrowserPageTabTransitionCoordinator();

    BrowserPageTabTransitionDeps buildDeps(List<String> calls) {
      return BrowserPageTabTransitionDeps(
        pauseCurrentWebView: () => calls.add('pause'),
        detachCurrentController: () => calls.add('detach'),
        unfocusAddressBar: () => calls.add('unfocus'),
        syncAddressBar: () => calls.add('sync-address'),
        checkFavoriteStatus: (url) async => calls.add('favorite:$url'),
        resetProgress: () => calls.add('progress'),
        trimBackgroundKeepAlives: () => calls.add('trim'),
      );
    }

    test(
      'prepareOpenedTab keeps opened-tab order without scroll sync',
      () async {
        final calls = <String>[];

        await coordinator.prepareOpenedTab(
          deps: buildDeps(calls),
          resetVideoDetectionState: () => calls.add('reset-video'),
          url: 'https://example.com',
          applyStatusAfterTransition: () => calls.add('status'),
          syncTrackedScrollPosition: () => calls.add('sync-scroll'),
        );

        expect(calls, <String>[
          'pause',
          'detach',
          'unfocus',
          'reset-video',
          'sync-address',
          'favorite:https://example.com',
          'progress',
          'status',
        ]);
      },
    );

    test(
      'prepareSwitchedTab syncs tracked scroll before address sync',
      () async {
        final calls = <String>[];

        await coordinator.prepareSwitchedTab(
          deps: buildDeps(calls),
          resetVideoDetectionState: () => calls.add('reset-video'),
          url: 'https://example.com',
          applyStatusAfterTransition: () => calls.add('status'),
          syncTrackedScrollPosition: () => calls.add('sync-scroll'),
        );

        expect(calls, <String>[
          'pause',
          'detach',
          'unfocus',
          'reset-video',
          'sync-scroll',
          'sync-address',
          'favorite:https://example.com',
          'progress',
          'status',
        ]);
      },
    );

    test('prepareClosedTab keeps retained WebViews before status', () async {
      final calls = <String>[];

      await coordinator.prepareClosedTab(
        deps: buildDeps(calls),
        url: 'https://example.com',
        applyStatusAfterTransition: () => calls.add('status'),
      );

      expect(calls, <String>[
        'pause',
        'detach',
        'unfocus',
        'sync-address',
        'favorite:https://example.com',
        'progress',
        'status',
      ]);
    });

    test('prepareCloseAllTabs uses close-all transition order', () async {
      final calls = <String>[];

      await coordinator.prepareCloseAllTabs(
        deps: buildDeps(calls),
        url: 'https://example.com',
        applyStatusAfterTransition: () => calls.add('status'),
      );

      expect(calls, <String>[
        'unfocus',
        'sync-address',
        'favorite:https://example.com',
        'progress',
        'status',
      ]);
    });

    test('decideCloseTabFollowUp delegates active-tab decision', () {
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
  });
}
