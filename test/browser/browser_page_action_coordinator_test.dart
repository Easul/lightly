import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_action_coordinator.dart';
import 'package:lightly/pages/browser_page_route_handler.dart';

void main() {
  group('BrowserPageActionCoordinator', () {
    const coordinator = BrowserPageActionCoordinator();

    test(
      'canShowFindInPage requires find availability and non-favorites page',
      () {
        expect(
          coordinator.canShowFindInPage(
            isFindAvailable: true,
            isFavoritesPage: false,
          ),
          isTrue,
        );
        expect(
          coordinator.canShowFindInPage(
            isFindAvailable: false,
            isFavoritesPage: false,
          ),
          isFalse,
        );
        expect(
          coordinator.canShowFindInPage(
            isFindAvailable: true,
            isFavoritesPage: true,
          ),
          isFalse,
        );
      },
    );

    test('applyDataManagementPlan executes enabled actions in order', () async {
      final calls = <String>[];
      await coordinator.applyDataManagementPlan(
        plan: const BrowserPageDataManagementActionPlan(
          reloadSettings: true,
          showFavoritesHome: false,
          refreshFavorites: true,
          reloadCurrentWebView: true,
          rebuild: true,
        ),
        reloadSettings: () async => calls.add('reloadSettings'),
        showFavoritesHome: () async => calls.add('showFavoritesHome'),
        refreshFavorites: () async => calls.add('refreshFavorites'),
        reloadCurrentWebView: () async => calls.add('reloadCurrentWebView'),
        rebuild: () => calls.add('rebuild'),
      );

      expect(calls, <String>[
        'reloadSettings',
        'refreshFavorites',
        'reloadCurrentWebView',
        'rebuild',
      ]);
    });
  });
}
