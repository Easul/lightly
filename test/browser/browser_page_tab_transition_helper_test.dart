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
        checkFavoriteStatus: (url) async => calls.add('checkFavoriteStatus'),
        resetProgress: () => calls.add('resetProgress'),
        trimBackgroundKeepAlives: () => calls.add('trimBackgroundKeepAlives'),
      );
    }

    test(
      'prepareOpenedOrSwitchedTab keeps background keepAlives intact',
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
          syncTrackedScroll: true,
        );

        expect(calls, isNot(contains('trimBackgroundKeepAlives')));
      },
    );

    test('prepareClosedTab trims background keepAlives', () async {
      final calls = <String>[];

      await helper.prepareClosedTab(
        deps: buildDeps(calls),
        url: 'https://example.com',
        applyStatusAfterTransition: () =>
            calls.add('applyStatusAfterTransition'),
      );

      expect(calls, contains('trimBackgroundKeepAlives'));
    });

    test('prepareCloseAllTabs trims background keepAlives', () async {
      final calls = <String>[];

      await helper.prepareCloseAllTabs(
        deps: buildDeps(calls),
        url: 'https://example.com',
        applyStatusAfterTransition: () =>
            calls.add('applyStatusAfterTransition'),
      );

      expect(calls, contains('trimBackgroundKeepAlives'));
    });
  });
}
