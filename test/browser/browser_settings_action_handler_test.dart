import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/clipboard_storage_service.dart';
import 'package:lightly/browser/models/browser_history_entry.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_cookie_origin_service.dart';
import 'package:lightly/browser/services/browser_history_service.dart';
import 'package:lightly/browser/services/browser_suggestion_service.dart';
import 'package:lightly/browser/services/browser_settings_action_handler.dart';
import 'package:lightly/features/calculator/history_service.dart' as calculator;

void main() {
  group('BrowserSettingsActionHandler', () {
    test('clearHistory delegates to history service', () async {
      final historyService = _FakeBrowserHistoryService();
      final suggestionService = _FakeBrowserSuggestionService();
      final handler = BrowserSettingsActionHandler(
        historyService: historyService,
        downloadService: _FakeBrowserDownloadService(),
        suggestionService: suggestionService,
      );

      await handler.clearHistory();

      expect(historyService.cleared, isTrue);
      expect(suggestionService.cacheCleared, isTrue);
    });

    test('clearBrowsingData clears selected local data categories', () async {
      final historyService = _FakeBrowserHistoryService();
      final suggestionService = _FakeBrowserSuggestionService();
      final downloadStore = _FakeBrowserDownloadStore();
      final favoriteService = _FakeBrowserFavoriteService();
      final clipboardStorage = _FakeClipboardStorageService();
      final calculatorHistoryService = _FakeCalculatorHistoryService();
      final handler = BrowserSettingsActionHandler(
        historyService: historyService,
        downloadService: _FakeBrowserDownloadService(),
        suggestionService: suggestionService,
        downloadStore: downloadStore,
        favoriteService: favoriteService,
        clipboardStorage: clipboardStorage,
        calculatorHistoryService: calculatorHistoryService,
      );

      await handler.clearBrowsingData(
        const BrowserClearDataSelection(
          history: true,
          downloadRecords: true,
          favorites: true,
          clipboard: true,
          calculatorHistory: true,
        ),
      );

      expect(historyService.cleared, isTrue);
      expect(suggestionService.cacheCleared, isTrue);
      expect(downloadStore.cleared, isTrue);
      expect(favoriteService.cleared, isTrue);
      expect(clipboardStorage.cleared, isTrue);
      expect(calculatorHistoryService.cleared, isTrue);
    });

    test(
      'clearBrowsingData clears cookie origin index with site data',
      () async {
        final cookieOriginService = _FakeBrowserCookieOriginService();
        var cookiesCleared = false;
        var webStorageCleared = false;
        final handler = BrowserSettingsActionHandler(
          historyService: _FakeBrowserHistoryService(),
          cookieOriginService: cookieOriginService,
          downloadService: _FakeBrowserDownloadService(),
          suggestionService: _FakeBrowserSuggestionService(),
          deleteAllCookies: () async {
            cookiesCleared = true;
          },
          deleteAllWebStorage: () async {
            webStorageCleared = true;
          },
        );

        await handler.clearBrowsingData(
          const BrowserClearDataSelection(cookiesAndSiteData: true),
        );

        expect(cookiesCleared, isTrue);
        expect(webStorageCleared, isTrue);
        expect(cookieOriginService.cleared, isTrue);
      },
    );

    test('clearBrowsingData skips work when selection is empty', () async {
      final historyService = _FakeBrowserHistoryService();
      final suggestionService = _FakeBrowserSuggestionService();
      final downloadStore = _FakeBrowserDownloadStore();
      final favoriteService = _FakeBrowserFavoriteService();
      final clipboardStorage = _FakeClipboardStorageService();
      final calculatorHistoryService = _FakeCalculatorHistoryService();
      final handler = BrowserSettingsActionHandler(
        historyService: historyService,
        downloadService: _FakeBrowserDownloadService(),
        suggestionService: suggestionService,
        downloadStore: downloadStore,
        favoriteService: favoriteService,
        clipboardStorage: clipboardStorage,
        calculatorHistoryService: calculatorHistoryService,
      );

      await handler.clearBrowsingData(const BrowserClearDataSelection());

      expect(historyService.cleared, isFalse);
      expect(suggestionService.cacheCleared, isFalse);
      expect(downloadStore.cleared, isFalse);
      expect(favoriteService.cleared, isFalse);
      expect(clipboardStorage.cleared, isFalse);
      expect(calculatorHistoryService.cleared, isFalse);
    });

    test('ensureLocalHttpFileAccessPermission reports granted state', () async {
      final handler = BrowserSettingsActionHandler(
        historyService: _FakeBrowserHistoryService(),
        downloadService: _FakeBrowserDownloadService(
          hasPermission: false,
          requestPermission: true,
        ),
      );

      final result = await handler.ensureLocalHttpFileAccessPermission();

      expect(result.granted, isTrue);
      expect(result.errorMessage, isNull);
    });

    test(
      'ensureLocalHttpFileAccessPermission returns platform error message',
      () async {
        final handler = BrowserSettingsActionHandler(
          historyService: _FakeBrowserHistoryService(),
          downloadService: _FakeBrowserDownloadService(
            throwPlatformException: true,
          ),
        );

        final result = await handler.ensureLocalHttpFileAccessPermission();

        expect(result.granted, isFalse);
        expect(result.errorMessage, '权限失败');
      },
    );

    test(
      'resolveSharedDownloadsDirectory delegates to download service',
      () async {
        final handler = BrowserSettingsActionHandler(
          historyService: _FakeBrowserHistoryService(),
          downloadService: _FakeBrowserDownloadService(
            sharedDownloadsPath: '/storage/emulated/0/Download',
          ),
        );

        final path = await handler.resolveSharedDownloadsDirectory();

        expect(path, '/storage/emulated/0/Download');
      },
    );
  });
}

class _FakeBrowserHistoryService extends BrowserHistoryService {
  bool cleared = false;

  @override
  Future<void> clearHistory() async {
    cleared = true;
  }

  @override
  Future<BrowserHistoryEntry> insert({
    required String url,
    required String title,
    DateTime? visitedAt,
  }) {
    throw UnimplementedError();
  }
}

class _FakeBrowserCookieOriginService extends BrowserCookieOriginService {
  bool cleared = false;

  @override
  Future<void> clearOrigins() async {
    cleared = true;
  }
}

class _FakeBrowserDownloadService extends BrowserDownloadService {
  _FakeBrowserDownloadService({
    this.hasPermission = true,
    this.requestPermission = true,
    this.sharedDownloadsPath,
    this.throwPlatformException = false,
  });

  final bool hasPermission;
  final bool requestPermission;
  final String? sharedDownloadsPath;
  final bool throwPlatformException;

  @override
  Future<bool> hasStoragePermission() async {
    if (throwPlatformException) {
      throw PlatformException(code: 'permission', message: '权限失败');
    }
    return hasPermission;
  }

  @override
  Future<bool> requestStoragePermission() async {
    return requestPermission;
  }

  @override
  Future<String?> getSystemDownloadPath() async {
    return sharedDownloadsPath;
  }
}

class _FakeBrowserSuggestionService extends BrowserSuggestionService {
  bool cacheCleared = false;

  @override
  void clearCache() {
    cacheCleared = true;
  }
}

class _FakeBrowserDownloadStore extends BrowserDownloadStore {
  bool cleared = false;

  @override
  Future<void> clearAll() async {
    cleared = true;
  }
}

class _FakeBrowserFavoriteService extends BrowserFavoriteService {
  bool cleared = false;

  @override
  Future<void> clearAll() async {
    cleared = true;
  }
}

class _FakeClipboardStorageService extends ClipboardStorageService {
  bool cleared = false;

  @override
  Future<void> clearContent() async {
    cleared = true;
  }
}

class _FakeCalculatorHistoryService extends calculator.HistoryService {
  bool cleared = false;

  @override
  Future<void> clearHistory() async {
    cleared = true;
  }
}
