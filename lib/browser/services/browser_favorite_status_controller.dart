import 'package:flutter/foundation.dart';

import 'browser_favorite_action_coordinator.dart';
import 'browser_favorite_service.dart';
import 'browser_favorite_status_tracker.dart';

class BrowserFavoriteStatusControllerResult {
  const BrowserFavoriteStatusControllerResult.success(this.message)
    : isError = false;

  const BrowserFavoriteStatusControllerResult.error(this.message)
    : isError = true;

  final String message;
  final bool isError;
}

class BrowserFavoriteStatusController {
  BrowserFavoriteStatusController({
    required BrowserFavoriteStatusTracker tracker,
    required BrowserFavoriteService favoriteService,
    required VoidCallback onStatusChanged,
  }) : _tracker = tracker,
       _actionCoordinator = BrowserFavoriteActionCoordinator(
         favoriteService: favoriteService,
       ),
       _onStatusChanged = onStatusChanged {
    _tracker.currentStatus.addListener(_onStatusChanged);
  }

  final BrowserFavoriteStatusTracker _tracker;
  final BrowserFavoriteActionCoordinator _actionCoordinator;
  final VoidCallback _onStatusChanged;

  ValueListenable<bool> get currentStatus => _tracker.currentStatus;
  bool get isCurrentPageFavorited => _tracker.isCurrentPageFavorited;

  Future<void> checkStatus(String url, {required bool isFavoritesPage}) {
    return _tracker.checkStatus(url, isFavoritesPage: isFavoritesPage);
  }

  Future<void> refreshStatus(String url, {required bool isFavoritesPage}) {
    return _tracker.refreshStatus(url, isFavoritesPage: isFavoritesPage);
  }

  void clearCache() {
    _tracker.clearCache();
  }

  Future<BrowserFavoriteStatusControllerResult?> toggleFavorite({
    required String url,
    required String title,
    required bool isFavoritesPage,
  }) async {
    try {
      final result = await _actionCoordinator.toggleFavorite(
        url: url,
        title: title,
        isFavoritesPage: isFavoritesPage,
        isCurrentlyFavorited: _tracker.isCurrentPageFavorited,
      );
      if (result == null) {
        return null;
      }
      _tracker.applyKnownStatus(url, result.isFavorited);
      return BrowserFavoriteStatusControllerResult.success(result.message);
    } catch (error) {
      return BrowserFavoriteStatusControllerResult.error('操作失败: $error');
    }
  }

  void dispose() {
    _tracker.currentStatus.removeListener(_onStatusChanged);
    _tracker.dispose();
  }
}
