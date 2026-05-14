import 'browser_favorite_service.dart';

class BrowserFavoriteToggleResult {
  const BrowserFavoriteToggleResult({
    required this.isFavorited,
    required this.message,
  });

  final bool isFavorited;
  final String message;
}

class BrowserFavoriteActionCoordinator {
  BrowserFavoriteActionCoordinator({BrowserFavoriteService? favoriteService})
    : _favoriteService = favoriteService ?? BrowserFavoriteService();

  final BrowserFavoriteService _favoriteService;

  Future<BrowserFavoriteToggleResult?> toggleFavorite({
    required String url,
    required String title,
    required bool isFavoritesPage,
    required bool isCurrentlyFavorited,
  }) async {
    if (url.isEmpty || isFavoritesPage) {
      return null;
    }

    if (isCurrentlyFavorited) {
      final favorite = await _favoriteService.findByUrl(url);
      if (favorite?.id != null) {
        await _favoriteService.delete(favorite!.id!);
      }
      return const BrowserFavoriteToggleResult(
        isFavorited: false,
        message: '已取消收藏',
      );
    }

    await _favoriteService.insert(url: url, title: title.isEmpty ? url : title);
    return const BrowserFavoriteToggleResult(
      isFavorited: true,
      message: '已添加到收藏',
    );
  }
}
