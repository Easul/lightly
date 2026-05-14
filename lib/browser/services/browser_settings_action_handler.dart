import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../calculator/history_service.dart' as calculator;
import '../clipboard_storage_service.dart';
import 'browser_download_service.dart';
import 'browser_download_store.dart';
import 'browser_favorite_service.dart';
import 'browser_history_service.dart';
import 'browser_suggestion_service.dart';

class BrowserFileAccessPermissionResult {
  const BrowserFileAccessPermissionResult({
    required this.granted,
    this.errorMessage,
  });

  final bool granted;
  final String? errorMessage;
}

class BrowserClearDataSelection {
  const BrowserClearDataSelection({
    this.history = false,
    this.cookiesAndSiteData = false,
    this.cache = false,
    this.downloadRecords = false,
    this.favorites = false,
    this.clipboard = false,
    this.calculatorHistory = false,
  });

  final bool history;
  final bool cookiesAndSiteData;
  final bool cache;
  final bool downloadRecords;
  final bool favorites;
  final bool clipboard;
  final bool calculatorHistory;

  bool get isEmpty =>
      !history &&
      !cookiesAndSiteData &&
      !cache &&
      !downloadRecords &&
      !favorites &&
      !clipboard &&
      !calculatorHistory;
}

class BrowserSettingsActionHandler {
  BrowserSettingsActionHandler({
    BrowserHistoryService? historyService,
    BrowserDownloadService? downloadService,
    BrowserSuggestionService? suggestionService,
    BrowserDownloadStore? downloadStore,
    BrowserFavoriteService? favoriteService,
    ClipboardStorageService? clipboardStorage,
    calculator.HistoryService? calculatorHistoryService,
  }) : _historyService = historyService ?? BrowserHistoryService(),
       _downloadService = downloadService ?? BrowserDownloadService(),
       _suggestionService =
           suggestionService ??
           BrowserSuggestionService(historyService: historyService),
       _downloadStore = downloadStore ?? BrowserDownloadStore(),
       _favoriteService = favoriteService ?? BrowserFavoriteService(),
       _clipboardStorage = clipboardStorage ?? ClipboardStorageService(),
       _calculatorHistoryService =
           calculatorHistoryService ?? calculator.HistoryService();

  final BrowserHistoryService _historyService;
  final BrowserDownloadService _downloadService;
  final BrowserSuggestionService _suggestionService;
  final BrowserDownloadStore _downloadStore;
  final BrowserFavoriteService _favoriteService;
  final ClipboardStorageService _clipboardStorage;
  final calculator.HistoryService _calculatorHistoryService;

  Future<void> clearHistory() async {
    await _historyService.clearHistory();
    _suggestionService.clearCache();
  }

  Future<void> clearBrowsingData(BrowserClearDataSelection selection) async {
    if (selection.isEmpty) {
      return;
    }

    if (selection.history) {
      await clearHistory();
    }
    if (selection.cookiesAndSiteData) {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
    }
    if (selection.cache) {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
    }
    if (selection.downloadRecords) {
      await _downloadStore.clearAll();
    }
    if (selection.favorites) {
      await _favoriteService.clearAll();
    }
    if (selection.clipboard) {
      await _clipboardStorage.clearContent();
    }
    if (selection.calculatorHistory) {
      await _calculatorHistoryService.clearHistory();
    }
  }

  Future<BrowserFileAccessPermissionResult>
  ensureLocalHttpFileAccessPermission() async {
    try {
      final alreadyGranted = await _downloadService.hasStoragePermission();
      if (alreadyGranted) {
        return const BrowserFileAccessPermissionResult(granted: true);
      }

      final granted = await _downloadService.requestStoragePermission();
      return BrowserFileAccessPermissionResult(granted: granted);
    } on PlatformException catch (error) {
      return BrowserFileAccessPermissionResult(
        granted: false,
        errorMessage: error.message ?? '文件访问权限请求失败',
      );
    }
  }

  Future<String?> resolveSharedDownloadsDirectory() async {
    return _downloadService.getSystemDownloadPath();
  }
}
