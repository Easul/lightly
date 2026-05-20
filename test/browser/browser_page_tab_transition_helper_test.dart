import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_tab_transition_helper.dart';

void main() {
  group('BrowserPageTabTransitionHelper', () {
    const helper = BrowserPageTabTransitionHelper();

    BrowserPageTabTransitionDeps buildDeps(List<String> calls) {
      return BrowserPageTabTransitionDeps(
        detachCurrentController: () => calls.add('detachCurrentController'),
        unfocusAddressBar: () => calls.add('unfocusAddressBar'),
        syncAddressBar: () => calls.add('syncAddressBar'),
        checkFavoriteStatus: (url) async =>
            calls.add('checkFavoriteStatus:$url'),
        resetProgress: () => calls.add('resetProgress'),
      );
    }

    test(
      'prepareOpenedOrSwitchedTab keeps transition order for open flow',
      () async {
        final calls = <String>[];

        await helper.prepareOpenedOrSwitchedTab(
          deps: buildDeps(calls),
          resetVideoDetectionState: () => calls.add('resetVideoDetectionState'),
          url: 'https://example.com',
          applyStatusAfterTransition: () =>
              calls.add('applyStatusAfterTransition'),
          syncTrackedScrollPosition: () =>
              calls.add('syncTrackedScrollPosition'),
          syncTrackedScroll: false,
        );

        expect(calls, <String>[
          'detachCurrentController',
          'unfocusAddressBar',
          'resetVideoDetectionState',
          'syncAddressBar',
          'checkFavoriteStatus:https://example.com',
          'resetProgress',
          'applyStatusAfterTransition',
        ]);
      },
    );

    test(
      'prepareOpenedOrSwitchedTab syncs tracked scroll for switch flow',
      () async {
        final calls = <String>[];

        await helper.prepareOpenedOrSwitchedTab(
          deps: buildDeps(calls),
          resetVideoDetectionState: () => calls.add('resetVideoDetectionState'),
          url: 'https://switch.example',
          applyStatusAfterTransition: () =>
              calls.add('applyStatusAfterTransition'),
          syncTrackedScrollPosition: () =>
              calls.add('syncTrackedScrollPosition'),
          syncTrackedScroll: true,
        );

        expect(calls, <String>[
          'detachCurrentController',
          'unfocusAddressBar',
          'resetVideoDetectionState',
          'syncTrackedScrollPosition',
          'syncAddressBar',
          'checkFavoriteStatus:https://switch.example',
          'resetProgress',
          'applyStatusAfterTransition',
        ]);
      },
    );

    test('prepareClosedTab keeps detach and status order', () async {
      final calls = <String>[];

      await helper.prepareClosedTab(
        deps: buildDeps(calls),
        url: 'https://closed.example',
        applyStatusAfterTransition: () =>
            calls.add('applyStatusAfterTransition'),
      );

      expect(calls, <String>[
        'detachCurrentController',
        'unfocusAddressBar',
        'syncAddressBar',
        'checkFavoriteStatus:https://closed.example',
        'resetProgress',
        'applyStatusAfterTransition',
      ]);
    });

    test('prepareCloseAllTabs leaves controller attached', () async {
      final calls = <String>[];

      await helper.prepareCloseAllTabs(
        deps: buildDeps(calls),
        url: 'https://favorites.example',
        applyStatusAfterTransition: () =>
            calls.add('applyStatusAfterTransition'),
      );

      expect(calls, <String>[
        'unfocusAddressBar',
        'syncAddressBar',
        'checkFavoriteStatus:https://favorites.example',
        'resetProgress',
        'applyStatusAfterTransition',
      ]);
    });
  });
}
