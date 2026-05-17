import '../browser/services/browser_favorite_action_coordinator.dart';
import '../browser/services/browser_favorite_status_tracker.dart';

class BrowserPageFavoriteToggleResult {
  const BrowserPageFavoriteToggleResult.success(this.message) : isError = false;

  const BrowserPageFavoriteToggleResult.error(this.message) : isError = true;

  final String message;
  final bool isError;
}

class BrowserPageFavoriteHelper {
  const BrowserPageFavoriteHelper();

  Future<void> checkFavoriteStatus({
    required BrowserFavoriteStatusTracker tracker,
    required String url,
    required bool isFavoritesPage,
  }) {
    return tracker.checkStatus(url, isFavoritesPage: isFavoritesPage);
  }

  Future<BrowserPageFavoriteToggleResult?> toggleFavorite({
    required BrowserFavoriteActionCoordinator coordinator,
    required BrowserFavoriteStatusTracker tracker,
    required String url,
    required String title,
    required bool isFavoritesPage,
  }) async {
    try {
      final result = await coordinator.toggleFavorite(
        url: url,
        title: title,
        isFavoritesPage: isFavoritesPage,
        isCurrentlyFavorited: tracker.isCurrentPageFavorited,
      );
      if (result == null) {
        return null;
      }
      tracker.applyKnownStatus(url, result.isFavorited);
      return BrowserPageFavoriteToggleResult.success(result.message);
    } catch (error) {
      return BrowserPageFavoriteToggleResult.error('操作失败: $error');
    }
  }
}
