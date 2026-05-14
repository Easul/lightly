import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/models/browser_favorite.dart';
import 'package:lightly/browser/services/browser_favorite_action_coordinator.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';

void main() {
  group('BrowserFavoriteActionCoordinator', () {
    late _FakeBrowserFavoriteService service;
    late BrowserFavoriteActionCoordinator coordinator;

    setUp(() {
      service = _FakeBrowserFavoriteService();
      coordinator = BrowserFavoriteActionCoordinator(favoriteService: service);
    });

    test('returns null for empty or favorites page url', () async {
      expect(
        await coordinator.toggleFavorite(
          url: '',
          title: '',
          isFavoritesPage: false,
          isCurrentlyFavorited: false,
        ),
        isNull,
      );
      expect(
        await coordinator.toggleFavorite(
          url: 'ruoqing://favorites',
          title: '',
          isFavoritesPage: true,
          isCurrentlyFavorited: false,
        ),
        isNull,
      );
    });

    test('adds favorite when page is not yet favorited', () async {
      final result = await coordinator.toggleFavorite(
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
        isCurrentlyFavorited: false,
      );

      expect(result, isNotNull);
      expect(result!.isFavorited, isTrue);
      expect(result.message, '已添加到收藏');
      expect(service.insertedUrl, 'https://example.com');
      expect(service.insertedTitle, 'Example');
    });

    test('removes favorite when page is already favorited', () async {
      service.favoriteToFind = BrowserFavorite(
        id: 7,
        url: 'https://example.com',
        title: 'Example',
        createdAt: DateTime(2024),
        sortOrder: 0,
      );

      final result = await coordinator.toggleFavorite(
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
        isCurrentlyFavorited: true,
      );

      expect(result, isNotNull);
      expect(result!.isFavorited, isFalse);
      expect(result.message, '已取消收藏');
      expect(service.deletedId, 7);
    });
  });
}

class _FakeBrowserFavoriteService extends BrowserFavoriteService {
  BrowserFavorite? favoriteToFind;
  String? insertedUrl;
  String? insertedTitle;
  int? deletedId;

  @override
  Future<BrowserFavorite?> findByUrl(String url) async => favoriteToFind;

  @override
  Future<BrowserFavorite> insert({
    required String url,
    required String title,
    int? sortOrder,
  }) async {
    insertedUrl = url;
    insertedTitle = title;
    return BrowserFavorite(
      id: 1,
      url: url,
      title: title,
      createdAt: DateTime(2024),
      sortOrder: sortOrder ?? 0,
    );
  }

  @override
  Future<void> delete(int id) async {
    deletedId = id;
  }
}
