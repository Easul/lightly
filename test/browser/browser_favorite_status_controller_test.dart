import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_favorite_status_controller.dart';
import 'package:lightly/browser/services/browser_favorite_status_tracker.dart';

void main() {
  group('BrowserFavoriteStatusController', () {
    test('checks status and notifies listeners', () async {
      var notifications = 0;
      final service = _FakeFavoriteService(
        favorites: <String, BrowserFavorite>{
          'https://example.com': _favorite('https://example.com'),
        },
      );
      final tracker = BrowserFavoriteStatusTracker(favoriteService: service);
      final controller = BrowserFavoriteStatusController(
        tracker: tracker,
        favoriteService: service,
        onStatusChanged: () => notifications++,
      );

      await controller.refreshStatus(
        'https://example.com',
        isFavoritesPage: false,
      );

      expect(controller.isCurrentPageFavorited, isTrue);
      expect(notifications, 1);
      controller.dispose();
    });

    test('toggle favorite applies known status', () async {
      var notifications = 0;
      final service = _FakeFavoriteService();
      final tracker = BrowserFavoriteStatusTracker(favoriteService: service);
      final controller = BrowserFavoriteStatusController(
        tracker: tracker,
        favoriteService: service,
        onStatusChanged: () => notifications++,
      );

      final addResult = await controller.toggleFavorite(
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
      );

      expect(addResult, isNotNull);
      expect(addResult!.isError, isFalse);
      expect(addResult.message, '已添加到收藏');
      expect(controller.isCurrentPageFavorited, isTrue);

      final removeResult = await controller.toggleFavorite(
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
      );

      expect(removeResult, isNotNull);
      expect(removeResult!.isError, isFalse);
      expect(removeResult.message, '已取消收藏');
      expect(controller.isCurrentPageFavorited, isFalse);
      expect(notifications, 2);
      controller.dispose();
    });

    test('toggle favorite returns null on favorites page', () async {
      final service = _FakeFavoriteService();
      final tracker = BrowserFavoriteStatusTracker(favoriteService: service);
      final controller = BrowserFavoriteStatusController(
        tracker: tracker,
        favoriteService: service,
        onStatusChanged: () {},
      );

      final result = await controller.toggleFavorite(
        url: 'ruoqing://favorites',
        title: '',
        isFavoritesPage: true,
      );

      expect(result, isNull);
      controller.dispose();
    });
  });
}

BrowserFavorite _favorite(String url, {int id = 1}) {
  return BrowserFavorite(
    id: id,
    url: url,
    title: url,
    createdAt: DateTime(2024),
    sortOrder: 0,
  );
}

class _FakeFavoriteService extends BrowserFavoriteService {
  _FakeFavoriteService({Map<String, BrowserFavorite>? favorites})
    : _favorites = Map<String, BrowserFavorite>.from(favorites ?? const {});

  final Map<String, BrowserFavorite> _favorites;
  int _nextId = 1;

  @override
  Future<BrowserFavorite?> findByUrl(String url) async => _favorites[url];

  @override
  Future<BrowserFavorite> insert({
    required String url,
    required String title,
    int? sortOrder,
  }) async {
    final favorite = BrowserFavorite(
      id: _nextId++,
      url: url,
      title: title,
      createdAt: DateTime(2024),
      sortOrder: sortOrder ?? 0,
    );
    _favorites[url] = favorite;
    return favorite;
  }

  @override
  Future<void> delete(int id) async {
    _favorites.removeWhere((_, favorite) => favorite.id == id);
  }
}
