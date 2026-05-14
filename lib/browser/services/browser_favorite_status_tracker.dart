import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser_favorite_service.dart';

class _LruCacheEntry<V> {
  final V value;
  int accessCount;
  DateTime lastAccessed;
  _LruCacheEntry(
    this.value, {
    this.accessCount = 1,
    required this.lastAccessed,
  });

  void touch() {
    accessCount++;
    lastAccessed = DateTime.now();
  }
}

class BrowserFavoriteStatusTracker {
  BrowserFavoriteStatusTracker({
    BrowserFavoriteService? favoriteService,
    int maxCacheSize = 100,
  }) : _favoriteService = favoriteService ?? BrowserFavoriteService(),
       _maxCacheSize = maxCacheSize;

  final BrowserFavoriteService _favoriteService;
  final ValueNotifier<bool> currentStatus = ValueNotifier<bool>(false);
  final int _maxCacheSize;

  int _requestId = 0;
  String _lastCheckedUrl = '';
  String? _pendingUrl;
  final Map<String, _LruCacheEntry<bool>> _statusCache = {};
  Timer? _debounceTimer;
  String? _debounceUrl;

  bool get isCurrentPageFavorited => currentStatus.value;

  void resetForFavoritesPage() {
    _lastCheckedUrl = '';
    _pendingUrl = null;
    _debounceTimer?.cancel();
    _debounceUrl = null;
    _setCurrentStatus(false);
  }

  void applyKnownStatus(String url, bool isFavorited) {
    _putCache(url, isFavorited);
    _lastCheckedUrl = url;
    _pendingUrl = null;
    _debounceTimer?.cancel();
    _debounceUrl = null;
    _setCurrentStatus(isFavorited);
  }

  void clearCache() {
    _statusCache.clear();
    _lastCheckedUrl = '';
    _pendingUrl = null;
    _debounceTimer?.cancel();
    _debounceUrl = null;
  }

  Future<void> refreshStatus(
    String url, {
    required bool isFavoritesPage,
  }) async {
    if (isFavoritesPage) {
      resetForFavoritesPage();
      return;
    }

    clearCache();
    await _executeStatusCheck(url);
  }

  Future<void> checkStatus(String url, {required bool isFavoritesPage}) async {
    if (isFavoritesPage) {
      resetForFavoritesPage();
      return;
    }

    final cachedEntry = _statusCache[url];
    if (cachedEntry != null) {
      cachedEntry.touch();
      _lastCheckedUrl = url;
      _pendingUrl = null;
      _debounceTimer?.cancel();
      _debounceUrl = null;
      _setCurrentStatus(cachedEntry.value);
      return;
    }

    if (_debounceUrl == url) {
      return;
    }
    _debounceUrl = url;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_executeStatusCheck(url));
    });
  }

  Future<void> _executeStatusCheck(String url) async {
    final requestId = ++_requestId;
    if (_pendingUrl == url || _lastCheckedUrl == url) {
      return;
    }

    _pendingUrl = url;
    try {
      final favorite = await _favoriteService.findByUrl(url);
      final isFavorited = favorite != null;
      _putCache(url, isFavorited);
      _lastCheckedUrl = url;
      _pendingUrl = null;
      if (requestId != _requestId) {
        return;
      }
      _setCurrentStatus(isFavorited);
    } catch (_) {
      if (_pendingUrl == url) {
        _pendingUrl = null;
      }
    }
  }

  void _putCache(String url, bool value) {
    if (_statusCache.length >= _maxCacheSize &&
        !_statusCache.containsKey(url)) {
      _evictIfNeeded();
    }
    _statusCache[url] = _LruCacheEntry<bool>(
      value,
      lastAccessed: DateTime.now(),
    );
  }

  void _evictIfNeeded() {
    if (_statusCache.isEmpty) return;

    // LFU + LRU hybrid eviction
    String? keyToEvict;
    int minAccessCount = -1;
    DateTime? oldestAccessTime;

    _statusCache.forEach((key, entry) {
      if (keyToEvict == null ||
          entry.accessCount < minAccessCount ||
          (entry.accessCount == minAccessCount &&
              entry.lastAccessed.isBefore(oldestAccessTime!))) {
        keyToEvict = key;
        minAccessCount = entry.accessCount;
        oldestAccessTime = entry.lastAccessed;
      }
    });

    if (keyToEvict != null) {
      _statusCache.remove(keyToEvict);
    }
  }

  void _setCurrentStatus(bool value) {
    if (currentStatus.value == value) {
      return;
    }
    currentStatus.value = value;
  }

  void dispose() {
    _debounceTimer?.cancel();
    currentStatus.dispose();
  }
}
