import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/browser_settings.dart';

class AppCacheCleanupResult {
  const AppCacheCleanupResult({
    required this.clearedEntries,
    required this.clearedDirectoryPaths,
  });

  final int clearedEntries;
  final List<String> clearedDirectoryPaths;
}

class AppCacheMaintenanceService {
  AppCacheMaintenanceService({
    Future<Directory> Function()? getTemporaryDirectoryFn,
    Future<Directory?> Function()? getApplicationCacheDirectoryFn,
    Future<void> Function()? clearWebViewCacheFn,
    Future<SharedPreferences> Function()? sharedPreferencesFactory,
  }) : _getTemporaryDirectory =
           getTemporaryDirectoryFn ?? getTemporaryDirectory,
       _getApplicationCacheDirectory =
           getApplicationCacheDirectoryFn ??
           _defaultGetApplicationCacheDirectory,
       _clearWebViewCache =
           clearWebViewCacheFn ??
           (() => InAppWebViewController.clearAllCache(includeDiskFiles: true)),
       _sharedPreferencesFactory =
           sharedPreferencesFactory ?? SharedPreferences.getInstance;

  static const String _lastCleanupAtKey = 'app_cache_last_cleanup_at_ms';

  final Future<Directory> Function() _getTemporaryDirectory;
  final Future<Directory?> Function() _getApplicationCacheDirectory;
  final Future<void> Function() _clearWebViewCache;
  final Future<SharedPreferences> Function() _sharedPreferencesFactory;

  static Future<Directory?> _defaultGetApplicationCacheDirectory() async {
    try {
      return await getApplicationCacheDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<AppCacheCleanupResult> clearAppCache({
    bool recordCleanupTime = true,
  }) async {
    final clearedPaths = <String>{};
    var clearedEntries = 0;

    final directories = <Directory?>[
      await _safeLoadDirectory(_getTemporaryDirectory),
      await _safeLoadDirectory(_getApplicationCacheDirectory),
    ];

    for (final directory in directories) {
      if (directory == null) {
        continue;
      }
      final resolvedPath = directory.path;
      if (resolvedPath.isEmpty || !clearedPaths.add(resolvedPath)) {
        continue;
      }
      clearedEntries += await _deleteDirectoryChildren(directory);
    }

    await _clearWebViewCache();
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();

    if (recordCleanupTime) {
      final prefs = await _sharedPreferencesFactory();
      await prefs.setInt(
        _lastCleanupAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }

    return AppCacheCleanupResult(
      clearedEntries: clearedEntries,
      clearedDirectoryPaths: clearedPaths.toList(growable: false),
    );
  }

  Future<bool> maybeAutoClear(BrowserSettings settings) async {
    if (!settings.appCacheAutoClearEnabled) {
      return false;
    }

    final interval = Duration(hours: settings.appCacheAutoClearIntervalHours);
    final lastCleanupAt = await loadLastCleanupAt();
    final now = DateTime.now();
    if (lastCleanupAt != null && now.difference(lastCleanupAt) < interval) {
      return false;
    }

    await clearAppCache(recordCleanupTime: true);
    return true;
  }

  Future<DateTime?> loadLastCleanupAt() async {
    final prefs = await _sharedPreferencesFactory();
    final rawValue = prefs.getInt(_lastCleanupAtKey);
    if (rawValue == null || rawValue <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(rawValue);
  }

  Future<Directory?> _safeLoadDirectory(
    Future<Directory?> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  Future<int> _deleteDirectoryChildren(Directory directory) async {
    if (!await directory.exists()) {
      return 0;
    }

    var deleted = 0;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }
}
