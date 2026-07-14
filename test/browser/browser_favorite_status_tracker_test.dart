import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_favorite_status_tracker.dart';

void main() {
  group('BrowserFavoriteStatusTracker', () {
    late _FakeBrowserFavoriteService favoriteService;
    late BrowserFavoriteStatusTracker tracker;

    setUp(() {
      favoriteService = _FakeBrowserFavoriteService();
      tracker = BrowserFavoriteStatusTracker(favoriteService: favoriteService);
    });

    tearDown(() {
      tracker.dispose();
    });

    test('resets immediately for favorites page', () async {
      tracker.applyKnownStatus('https://example.com', true);

      await tracker.checkStatus('ruoqing://favorites', isFavoritesPage: true);

      expect(tracker.isCurrentPageFavorited, isFalse);
    });

    test('applies known status immediately and caches it', () async {
      tracker.applyKnownStatus('https://example.com', true);

      await tracker.checkStatus('https://example.com', isFavoritesPage: false);

      expect(tracker.isCurrentPageFavorited, isTrue);
      expect(favoriteService.findByUrlCalls, 0);
    });

    test('loads favorite state after debounce when cache is empty', () async {
      favoriteService.favoriteByUrl['https://example.com'] = BrowserFavorite(
        id: 1,
        url: 'https://example.com',
        title: 'Example',
        createdAt: DateTime(2024),
        sortOrder: 0,
      );

      await tracker.checkStatus('https://example.com', isFavoritesPage: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(tracker.isCurrentPageFavorited, isTrue);
      expect(favoriteService.findByUrlCalls, 1);
    });

    test('clearCache forces next check to reload favorite status', () async {
      tracker.applyKnownStatus('https://example.com', true);
      favoriteService.favoriteByUrl.clear();

      tracker.clearCache();
      await tracker.checkStatus('https://example.com', isFavoritesPage: false);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(tracker.isCurrentPageFavorited, isFalse);
      expect(favoriteService.findByUrlCalls, 1);
    });

    test('refreshStatus bypasses cache and updates immediately', () async {
      tracker.applyKnownStatus('https://example.com', true);
      favoriteService.favoriteByUrl.clear();

      await tracker.refreshStatus(
        'https://example.com',
        isFavoritesPage: false,
      );

      expect(tracker.isCurrentPageFavorited, isFalse);
      expect(favoriteService.findByUrlCalls, 1);
    });
  });
}

class _FakeBrowserFavoriteService extends BrowserFavoriteService {
  final Map<String, BrowserFavorite> favoriteByUrl =
      <String, BrowserFavorite>{};
  int findByUrlCalls = 0;

  @override
  Future<BrowserFavorite?> findByUrl(String url) async {
    findByUrlCalls += 1;
    return favoriteByUrl[url];
  }
}
