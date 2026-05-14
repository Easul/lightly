import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_route_handler.dart';
import 'package:lightly/pages/data_management_page.dart';

void main() {
  group('BrowserPageRouteHandler', () {
    const handler = BrowserPageRouteHandler();

    test('reloads settings only when settings route returns true', () {
      expect(handler.shouldReloadSettingsAfterSettingsRoute(true), isTrue);
      expect(handler.shouldReloadSettingsAfterSettingsRoute(false), isFalse);
      expect(handler.shouldReloadSettingsAfterSettingsRoute(null), isFalse);
    });

    test(
      'plans favorites and web reload actions from data management result',
      () {
        final plan = handler.planDataManagementActions(
          result: const DataManagementPageResult(
            changed: true,
            favoritesChanged: true,
            settingsChanged: true,
            webDataChanged: true,
            restoredOrigins: <String>['https://example.com'],
          ),
          currentUrl: 'https://example.com/path',
          isFavoritesPage: false,
        );

        expect(plan.reloadSettings, isTrue);
        expect(plan.showFavoritesHome, isTrue);
        expect(plan.refreshFavorites, isTrue);
        expect(plan.reloadCurrentWebView, isTrue);
        expect(plan.rebuild, isTrue);
      },
    );

    test('falls back to full refresh for legacy boolean result', () {
      final plan = handler.planDataManagementActions(
        result: true,
        currentUrl: 'ruoqing://favorites',
        isFavoritesPage: true,
      );

      expect(plan.reloadSettings, isTrue);
      expect(plan.showFavoritesHome, isTrue);
      expect(plan.refreshFavorites, isTrue);
      expect(plan.reloadCurrentWebView, isFalse);
      expect(plan.rebuild, isTrue);
    });
  });
}
