import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/calculator/history_service.dart';
import '../../core/logging/runtime_logger.dart';
import '../../core/storage/shared_downloads_access.dart';
import '../../services/app_log_service.dart';
import '../../features/easytier/infrastructure/easytier_profile_service.dart';
import '../../features/local_sharing/simple_file_manager/simple_file_manager_service.dart';
import '../../features/local_sharing/simple_file_manager/simple_file_manager_settings_store.dart';
import '../../services/shared_downloads_directory_service.dart';
import '../../features/telegram/telegram_checkin_store.dart';
import '../../features/life_runtime/infrastructure/life_runtime_config_store.dart';
import '../browser_settings_service.dart';
import '../../features/local_sharing/clipboard/clipboard_storage_service.dart';
import '../models/browser_favorite.dart';
import '../models/browser_history_entry.dart';
import '../models/browser_download_record.dart';
import 'browser_favorite_service.dart';
import 'browser_history_service.dart';
import 'browser_download_store.dart';
import 'browser_backup_file_writer.dart';
import 'browser_backup_models.dart';
import 'browser_backup_web_data_service.dart';
import 'browser_cookie_origin_service.dart';

export 'browser_backup_models.dart';

class BrowserBackupService {
  BrowserBackupService({
    BrowserFavoriteService? favoriteService,
    BrowserSettingsService? settingsService,
    BrowserHistoryService? historyService,
    BrowserDownloadStore? downloadStore,
    BrowserCookieOriginService? cookieOriginService,
    HistoryService? calculatorHistoryService,
    ClipboardStorageService? clipboardStorageService,
    EasyTierProfileService? easyTierProfileService,
    TelegramCheckinStore? telegramCheckinStore,
    SimpleFileManagerSettingsStore? simpleFileManagerSettingsStore,
    SharedDownloadsAccess? sharedDownloadsAccess,
    RuntimeLogger? runtimeLogger,
    LifeRuntimeConfigStore? lifeRuntimeConfigStore,
  }) : _favoriteService = favoriteService ?? BrowserFavoriteService(),
       _settingsService = settingsService ?? BrowserSettingsService(),
       _historyService = historyService ?? BrowserHistoryService(),
       _downloadStore = downloadStore ?? BrowserDownloadStore(),
       _cookieOriginService =
           cookieOriginService ?? BrowserCookieOriginService(),
       _calculatorHistoryService = calculatorHistoryService ?? HistoryService(),
       _clipboardStorageService =
           clipboardStorageService ?? ClipboardStorageService(),
       _easyTierProfileService =
           easyTierProfileService ?? EasyTierProfileService(),
       _telegramCheckinStore = telegramCheckinStore ?? TelegramCheckinStore(),
       _simpleFileManagerSettingsStore =
           simpleFileManagerSettingsStore ?? SimpleFileManagerService(),
       _sharedDownloadsAccess =
           sharedDownloadsAccess ?? SharedDownloadsDirectoryService(),
       _runtimeLogger = runtimeLogger ?? AppLogService.instance,
       _lifeRuntimeConfigStore =
           lifeRuntimeConfigStore ?? LifeRuntimeConfigStore();

  final BrowserFavoriteService _favoriteService;
  final BrowserSettingsService _settingsService;
  final BrowserHistoryService _historyService;
  final BrowserDownloadStore _downloadStore;
  final BrowserCookieOriginService _cookieOriginService;
  final HistoryService _calculatorHistoryService;
  final ClipboardStorageService _clipboardStorageService;
  final EasyTierProfileService _easyTierProfileService;
  final TelegramCheckinStore _telegramCheckinStore;
  final SimpleFileManagerSettingsStore _simpleFileManagerSettingsStore;
  final SharedDownloadsAccess _sharedDownloadsAccess;
  final RuntimeLogger _runtimeLogger;
  final LifeRuntimeConfigStore _lifeRuntimeConfigStore;
  late final BrowserBackupWebDataService _webDataService =
      BrowserBackupWebDataService(
        cookieOriginService: _cookieOriginService,
        logDebug: _logDebug,
      );
  late final BrowserBackupFileWriter _fileWriter = BrowserBackupFileWriter(
    sharedDownloadsAccess: _sharedDownloadsAccess,
  );

  void _logDebug(
    String message, {
    Object? error,
    Map<String, Object?>? metadata,
  }) {
    recordRuntimeLog(
      'BrowserBackup',
      message,
      error: error,
      metadata: metadata,
      service: _runtimeLogger,
    );
  }

  Future<BrowserBackupData> exportData() async {
    final favorites = await _favoriteService.query();
    final settings = await _settingsService.loadSettings();
    final history = await _historyService.query(limit: 1000);
    final downloads = await _downloadStore.list(limit: null);
    final calculatorHistory = await _calculatorHistoryService.loadHistory();
    final clipboardContent = await _clipboardStorageService.loadContent();
    final clipboardPort = await _clipboardStorageService.loadServerPort();
    final clipboardEnabled = await _clipboardStorageService.loadServerEnabled();
    final easyTierProfiles = await _easyTierProfileService.loadProfiles();
    final selectedEasyTierProfileId = await _easyTierProfileService
        .getSelectedProfileId();
    final telegramCheckinConfig = await _telegramCheckinStore.load();
    final simpleFileManagerSettings = await _simpleFileManagerSettingsStore
        .loadSettings();
    final lifeRuntimeConfig = await _lifeRuntimeConfigStore.load();
    final cookieUrls = await _webDataService.collectCookieUrls();
    final cookies = await _webDataService.exportCookies(urls: cookieUrls);
    final webStorageOrigins = _webDataService.collectWebStorageOrigins(
      history: history,
      favorites: favorites,
      homepageUrl: settings.homepageUrl,
      cookies: cookies,
    );
    final webStorage = await _webDataService.exportWebStorage(
      origins: webStorageOrigins,
    );

    return BrowserBackupData(
      favorites: favorites,
      settings: settings,
      history: history,
      downloads: downloads,
      calculatorHistory: calculatorHistory,
      clipboardContent: clipboardContent,
      clipboardPort: clipboardEnabled ? clipboardPort : null,
      cookies: cookies,
      webStorage: webStorage,
      easyTierProfiles: easyTierProfiles,
      selectedEasyTierProfileId: selectedEasyTierProfileId,
      telegramCheckinConfig: telegramCheckinConfig,
      exportedAt: DateTime.now(),
      simpleFileManagerFavoritePaths: simpleFileManagerSettings.favoritePaths,
      lifeRuntimeConfig: lifeRuntimeConfig,
    );
  }

  Future<File> exportToDownloads({
    bool requestSharedAccessIfNeeded = true,
  }) async {
    final backup = await exportData();
    return _fileWriter.writeToDownloads(
      backup,
      requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
    );
  }

  Future<void> copyToClipboard() async {
    final backup = await exportData();
    await Clipboard.setData(ClipboardData(text: backup.toJsonString()));
  }

  Future<BrowserBackupData> importFromJson(String json) async {
    return BrowserBackupData.fromJsonString(json);
  }

  Future<ImportResult> importData(
    BrowserBackupData data, {
    bool mergeFavorites = true,
    bool importSettings = true,
    bool importHistory = true,
    bool importDownloads = true,
    bool importClipboard = true,
    bool importCalculatorHistory = true,
    bool importWebData = true,
    bool importEasyTierProfiles = true,
  }) async {
    var favoritesImported = 0;
    var historyImported = 0;
    var downloadsImported = 0;
    var calculatorImported = 0;
    var cookiesImported = 0;
    var webStorageImported = 0;
    var easyTierProfilesImported = 0;
    final restoredOrigins = <String>{};

    if (mergeFavorites) {
      final existingFavorites = await _favoriteService.query();
      final existingUrls = existingFavorites.map((e) => e.url).toSet();
      for (final favorite in data.favorites) {
        if (!existingUrls.contains(favorite.url)) {
          await _favoriteService.insert(
            title: favorite.title,
            url: favorite.url,
          );
          favoritesImported++;
        }
      }
    } else {
      await _favoriteService.clearAll();
      for (final favorite in data.favorites) {
        await _favoriteService.insert(title: favorite.title, url: favorite.url);
        favoritesImported++;
      }
    }

    if (importSettings) {
      await _settingsService.saveSettings(data.settings);
      if (data.lifeRuntimeConfig != null) {
        await _lifeRuntimeConfigStore.save(data.lifeRuntimeConfig!);
      }
      await _telegramCheckinStore.save(data.telegramCheckinConfig);
      final favoritePaths = data.simpleFileManagerFavoritePaths;
      if (favoritePaths != null) {
        final currentSettings = await _simpleFileManagerSettingsStore
            .loadSettings();
        await _simpleFileManagerSettingsStore.saveSettings(
          currentSettings.copyWith(favoritePaths: favoritePaths),
        );
      }
    }

    if (importHistory && data.history.isNotEmpty) {
      for (final item in data.history.reversed) {
        try {
          await _historyService.insert(
            url: item.url,
            title: item.title,
            visitedAt: item.visitedAt,
          );
          historyImported++;
        } catch (_) {}
      }
    }

    if (importDownloads && data.downloads.isNotEmpty) {
      final existingDownloads = await _downloadStore.list(limit: null);
      final existingKeys = existingDownloads
          .map(_downloadDeduplicationKey)
          .toSet();
      for (final item in data.downloads.reversed) {
        final normalized = _normalizeImportedDownload(item);
        if (normalized == null) {
          continue;
        }
        final key = _downloadDeduplicationKey(normalized);
        if (!existingKeys.add(key)) {
          continue;
        }
        await _downloadStore.insert(normalized);
        downloadsImported++;
      }
    }

    if (importClipboard) {
      await _clipboardStorageService.saveContent(data.clipboardContent);
      if (data.clipboardPort != null) {
        await _clipboardStorageService.saveServerPort(data.clipboardPort);
        await _clipboardStorageService.saveServerEnabled(true);
      }
    }

    if (importCalculatorHistory) {
      await _calculatorHistoryService.clearHistory();
      for (final item in data.calculatorHistory.reversed) {
        await _calculatorHistoryService.saveEntry(item);
        calculatorImported++;
      }
    }

    if (importWebData && data.cookies.isNotEmpty) {
      cookiesImported = await _webDataService.importCookies(data.cookies);
      restoredOrigins.addAll(
        data.cookies
            .map((cookie) => cookie['url'] as String?)
            .whereType<String>()
            .map(_webDataService.normalizeOrigin)
            .whereType<String>(),
      );
    }

    if (importWebData && data.webStorage.isNotEmpty) {
      webStorageImported = await _webDataService.importWebStorage(
        data.webStorage,
      );
      restoredOrigins.addAll(
        data.webStorage
            .map((entry) => entry['origin'] as String?)
            .whereType<String>()
            .map(_webDataService.normalizeOrigin)
            .whereType<String>(),
      );
    }

    if (importEasyTierProfiles && data.easyTierProfiles.isNotEmpty) {
      await _easyTierProfileService.saveProfiles(data.easyTierProfiles);
      if (data.selectedEasyTierProfileId != null) {
        await _easyTierProfileService.setSelectedProfileId(
          data.selectedEasyTierProfileId!,
        );
      }
      easyTierProfilesImported = data.easyTierProfiles.length;
    }

    return ImportResult(
      favoritesImported: favoritesImported,
      historyImported: historyImported,
      downloadsImported: downloadsImported,
      calculatorImported: calculatorImported,
      cookiesImported: cookiesImported,
      webStorageImported: webStorageImported,
      easyTierProfilesImported: easyTierProfilesImported,
      settingsUpdated: importSettings,
      clipboardUpdated: importClipboard,
      restoredOrigins: restoredOrigins.toList(growable: false),
    );
  }

  BrowserDownloadRecord? _normalizeImportedDownload(
    BrowserDownloadRecord record,
  ) {
    if (record.url.trim().isEmpty ||
        record.fileName.trim().isEmpty ||
        record.createdAt.millisecondsSinceEpoch <= 0) {
      return null;
    }
    final status = switch (record.status) {
      'completed' || 'paused' || 'failed' => record.status,
      'pending' || 'downloading' => 'paused',
      _ => 'failed',
    };
    return BrowserDownloadRecord(
      url: record.url,
      fileName: record.fileName,
      status: status,
      savedPath: record.savedPath,
      totalBytes: record.totalBytes < 0 ? 0 : record.totalBytes,
      bytesReceived: record.bytesReceived < 0 ? 0 : record.bytesReceived,
      createdAt: record.createdAt,
    );
  }

  String _downloadDeduplicationKey(BrowserDownloadRecord record) {
    return '${record.url}\u0000${record.savedPath ?? ''}\u0000'
        '${record.createdAt.millisecondsSinceEpoch}';
  }

  String? validateImportJson(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        return '备份内容不是有效对象';
      }
      final version = (decoded['version'] as num?)?.toInt() ?? 0;
      if (version < 1) {
        return '备份版本无效';
      }
      if (decoded['settings'] == null && decoded['favorites'] == null) {
        return '备份内容为空';
      }
      return null;
    } catch (e) {
      return 'JSON 格式错误：$e';
    }
  }

  @visibleForTesting
  Future<Set<String>> collectCookieUrlsForTesting() {
    return _webDataService.collectCookieUrls();
  }

  @visibleForTesting
  Set<String> collectWebStorageOriginsForTesting({
    required List<BrowserHistoryEntry> history,
    required List<BrowserFavorite> favorites,
    required String homepageUrl,
    required List<Map<String, dynamic>> cookies,
  }) {
    return _webDataService.collectWebStorageOrigins(
      history: history,
      favorites: favorites,
      homepageUrl: homepageUrl,
      cookies: cookies,
    );
  }

  @visibleForTesting
  String? normalizeCookieLookupUrlForTesting(String rawUrl) {
    return _webDataService.normalizeCookieLookupUrl(rawUrl);
  }
}
