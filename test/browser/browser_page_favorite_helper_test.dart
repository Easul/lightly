import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_favorite_action_coordinator.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_favorite_status_tracker.dart';
import 'package:lightly/pages/browser_page_favorite_helper.dart';

void main() {
  group('BrowserPageFavoriteHelper', () {
    const helper = BrowserPageFavoriteHelper();

    test(
      'checkFavoriteStatus forwards favorites-page resets to tracker',
      () async {
        final tracker = BrowserFavoriteStatusTracker(
          favoriteService: _FakeBrowserFavoriteService(),
        );
        tracker.currentStatus.value = true;

        await helper.checkFavoriteStatus(
          tracker: tracker,
          url: 'ruoqing://favorites',
          isFavoritesPage: true,
        );

        expect(tracker.isCurrentPageFavorited, isFalse);
        tracker.dispose();
      },
    );

    test('toggleFavorite applies known favorited status on success', () async {
      final tracker = BrowserFavoriteStatusTracker(
        favoriteService: _FakeBrowserFavoriteService(),
      );
      final coordinator = _FakeFavoriteActionCoordinator(
        result: const BrowserFavoriteToggleResult(
          isFavorited: true,
          message: '已添加到收藏',
        ),
      );

      final result = await helper.toggleFavorite(
        coordinator: coordinator,
        tracker: tracker,
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
      );

      expect(result, isNotNull);
      expect(result!.isError, isFalse);
      expect(result.message, '已添加到收藏');
      expect(tracker.isCurrentPageFavorited, isTrue);
      tracker.dispose();
    });

    test('toggleFavorite returns null when coordinator returns null', () async {
      final tracker = BrowserFavoriteStatusTracker(
        favoriteService: _FakeBrowserFavoriteService(),
      );
      final coordinator = _FakeFavoriteActionCoordinator(result: null);

      final result = await helper.toggleFavorite(
        coordinator: coordinator,
        tracker: tracker,
        url: '',
        title: '',
        isFavoritesPage: false,
      );

      expect(result, isNull);
      expect(tracker.isCurrentPageFavorited, isFalse);
      tracker.dispose();
    });

    test('toggleFavorite wraps coordinator errors for UI display', () async {
      final tracker = BrowserFavoriteStatusTracker(
        favoriteService: _FakeBrowserFavoriteService(),
      );
      final coordinator = _FakeFavoriteActionCoordinator(
        error: StateError('boom'),
      );

      final result = await helper.toggleFavorite(
        coordinator: coordinator,
        tracker: tracker,
        url: 'https://example.com',
        title: 'Example',
        isFavoritesPage: false,
      );

      expect(result, isNotNull);
      expect(result!.isError, isTrue);
      expect(result.message, contains('操作失败:'));
      expect(result.message, contains('boom'));
      tracker.dispose();
    });
  });
}

class _FakeBrowserFavoriteService extends BrowserFavoriteService {}

class _FakeFavoriteActionCoordinator extends BrowserFavoriteActionCoordinator {
  _FakeFavoriteActionCoordinator({this.result, this.error});

  final BrowserFavoriteToggleResult? result;
  final Object? error;

  @override
  Future<BrowserFavoriteToggleResult?> toggleFavorite({
    required String url,
    required String title,
    required bool isFavoritesPage,
    required bool isCurrentlyFavorited,
  }) async {
    if (error != null) {
      throw error!;
    }
    return result;
  }
}
