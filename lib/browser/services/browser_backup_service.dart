import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;

import '../../calculator/calculation_history.dart';
import '../../calculator/history_service.dart';
import '../../models/easytier_network_profile.dart';
import '../../services/easytier_profile_service.dart';
import '../../services/shared_downloads_directory_service.dart';
import '../browser_settings.dart';
import '../browser_settings_service.dart';
import '../clipboard_storage_service.dart';
import '../models/browser_favorite.dart';
import '../models/browser_history_entry.dart';
import 'browser_favorite_service.dart';
import 'browser_history_service.dart';

class BrowserBackupData {
  const BrowserBackupData({
    required this.favorites,
    required this.settings,
    required this.history,
    required this.calculatorHistory,
    required this.clipboardContent,
    required this.clipboardPort,
    required this.cookies,
    required this.webStorage,
    required this.easyTierProfiles,
    required this.selectedEasyTierProfileId,
    required this.exportedAt,
  });

  final List<BrowserFavorite> favorites;
  final BrowserSettings settings;
  final List<BrowserHistoryEntry> history;
  final List<CalculationHistory> calculatorHistory;
  final String clipboardContent;
  final int? clipboardPort;
  final List<Map<String, dynamic>> cookies;
  final List<Map<String, dynamic>> webStorage;
  final List<EasyTierNetworkProfile> easyTierProfiles;
  final String? selectedEasyTierProfileId;
  final DateTime exportedAt;

  Map<String, dynamic> toJson() {
    return {
      'version': 7,
      'exportedAt': exportedAt.toIso8601String(),
      'favorites': favorites.map((f) => f.toMap()).toList(),
      'settings': settings.toJson(),
      'history': history.map((h) => h.toMap()).toList(),
      'calculatorHistory': calculatorHistory.map((h) => h.toJson()).toList(),
      'clipboardContent': clipboardContent,
      'clipboardPort': clipboardPort,
      'cookies': cookies,
      'webStorage': webStorage,
      'easyTierProfiles': easyTierProfiles
          .map((profile) => profile.toJson())
          .toList(),
      'selectedEasyTierProfileId': selectedEasyTierProfileId,
    };
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory BrowserBackupData.fromJsonString(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final favorites = (decoded['favorites'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              BrowserFavorite.fromMap(Map<String, Object?>.from(item as Map)),
        )
        .toList();
    final settings = BrowserSettings.fromJson(
      Map<String, dynamic>.from(decoded['settings'] as Map? ?? const {}),
    );
    final history = (decoded['history'] as List<dynamic>? ?? const [])
        .map(
          (item) => BrowserHistoryEntry.fromMap(
            Map<String, Object?>.from(item as Map),
          ),
        )
        .toList();
    final calculatorHistory =
        (decoded['calculatorHistory'] as List<dynamic>? ?? const [])
            .map(
              (item) => CalculationHistory.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    final cookies = (decoded['cookies'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final webStorage = (decoded['webStorage'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final easyTierProfiles =
        (decoded['easyTierProfiles'] as List<dynamic>? ?? const [])
            .map(
              (item) => EasyTierNetworkProfile.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
    return BrowserBackupData(
      favorites: favorites,
      settings: settings,
      history: history,
      calculatorHistory: calculatorHistory,
      clipboardContent: decoded['clipboardContent'] as String? ?? '',
      clipboardPort: (decoded['clipboardPort'] as num?)?.toInt(),
      cookies: cookies,
      webStorage: webStorage,
      easyTierProfiles: easyTierProfiles,
      selectedEasyTierProfileId:
          decoded['selectedEasyTierProfileId'] as String?,
      exportedAt:
          DateTime.tryParse(decoded['exportedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ImportResult {
  const ImportResult({
    required this.favoritesImported,
    required this.historyImported,
    required this.calculatorImported,
    required this.cookiesImported,
    required this.webStorageImported,
    required this.easyTierProfilesImported,
    required this.settingsUpdated,
    required this.clipboardUpdated,
    required this.restoredOrigins,
  });

  final int favoritesImported;
  final int historyImported;
  final int calculatorImported;
  final int cookiesImported;
  final int webStorageImported;
  final int easyTierProfilesImported;
  final bool settingsUpdated;
  final bool clipboardUpdated;
  final List<String> restoredOrigins;

  @override
  String toString() {
    final parts = <String>[
      if (favoritesImported > 0) '$favoritesImported 个收藏',
      if (historyImported > 0) '$historyImported 条浏览历史',
      if (calculatorImported > 0) '$calculatorImported 条计算器历史',
      if (cookiesImported > 0) '$cookiesImported 个 Cookie',
      if (webStorageImported > 0) '$webStorageImported 个站点存储',
      if (easyTierProfilesImported > 0) '$easyTierProfilesImported 个 VPN 配置',
      if (settingsUpdated) '设置',
      if (clipboardUpdated) '剪贴板',
    ];
    return parts.isEmpty ? '无数据更新' : parts.join('、');
  }
}

class BrowserBackupService {
  static const Set<String> _supplementalCookieOrigins = <String>{
    'https://oauth.telegram.org',
    'https://accounts.google.com',
    'https://login.microsoftonline.com',
    'https://appleid.apple.com',
  };
  static const Duration _webStorageExportTimeout = Duration(seconds: 4);

  BrowserBackupService({
    BrowserFavoriteService? favoriteService,
    BrowserSettingsService? settingsService,
    BrowserHistoryService? historyService,
    HistoryService? calculatorHistoryService,
    ClipboardStorageService? clipboardStorageService,
    EasyTierProfileService? easyTierProfileService,
    SharedDownloadsDirectoryService? sharedDownloadsDirectoryService,
  }) : _favoriteService = favoriteService ?? BrowserFavoriteService(),
       _settingsService = settingsService ?? BrowserSettingsService(),
       _historyService = historyService ?? BrowserHistoryService(),
       _calculatorHistoryService = calculatorHistoryService ?? HistoryService(),
       _clipboardStorageService =
           clipboardStorageService ?? ClipboardStorageService(),
       _easyTierProfileService =
           easyTierProfileService ?? EasyTierProfileService(),
       _sharedDownloadsDirectoryService =
           sharedDownloadsDirectoryService ?? SharedDownloadsDirectoryService();

  final BrowserFavoriteService _favoriteService;
  final BrowserSettingsService _settingsService;
  final BrowserHistoryService _historyService;
  final HistoryService _calculatorHistoryService;
  final ClipboardStorageService _clipboardStorageService;
  final EasyTierProfileService _easyTierProfileService;
  final SharedDownloadsDirectoryService _sharedDownloadsDirectoryService;

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  Future<BrowserBackupData> exportData() async {
    final favorites = await _favoriteService.query();
    final settings = await _settingsService.loadSettings();
    final history = await _historyService.query(limit: 1000);
    final calculatorHistory = await _calculatorHistoryService.loadHistory();
    final clipboardContent = await _clipboardStorageService.loadContent();
    final clipboardPort = await _clipboardStorageService.loadServerPort();
    final clipboardEnabled = await _clipboardStorageService.loadServerEnabled();
    final easyTierProfiles = await _easyTierProfileService.loadProfiles();
    final selectedEasyTierProfileId = await _easyTierProfileService
        .getSelectedProfileId();
    final cookieOrigins = _collectCookieOrigins(
      history: history,
      favorites: favorites,
      homepageUrl: settings.homepageUrl,
    );
    final cookies = await _exportCookies(origins: cookieOrigins);
    final webStorageOrigins = _collectWebStorageOrigins(
      history: history,
      favorites: favorites,
      homepageUrl: settings.homepageUrl,
      cookies: cookies,
    );
    final webStorage = await _exportWebStorage(origins: webStorageOrigins);

    return BrowserBackupData(
      favorites: favorites,
      settings: settings,
      history: history,
      calculatorHistory: calculatorHistory,
      clipboardContent: clipboardContent,
      clipboardPort: clipboardEnabled ? clipboardPort : null,
      cookies: cookies,
      webStorage: webStorage,
      easyTierProfiles: easyTierProfiles,
      selectedEasyTierProfileId: selectedEasyTierProfileId,
      exportedAt: DateTime.now(),
    );
  }

  Future<File> exportToDownloads({
    bool requestSharedAccessIfNeeded = true,
  }) async {
    final backup = await exportData();
    final downloadDirectory = await _sharedDownloadsDirectoryService
        .resolveDirectory(
          preferSharedDownloads: true,
          requestSharedAccessIfNeeded: requestSharedAccessIfNeeded,
          androidFallbackFolderName: 'exports',
          nonAndroidFallbackFolderName: 'exports',
        );

    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final file = File(
      path.join(downloadDirectory.path, 'ruoqing-$timestamp.json'),
    );
    await file.writeAsString(backup.toJsonString());
    return file;
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
    bool importClipboard = true,
    bool importCalculatorHistory = true,
    bool importWebData = true,
    bool importEasyTierProfiles = true,
  }) async {
    var favoritesImported = 0;
    var historyImported = 0;
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
      cookiesImported = await _importCookies(data.cookies);
      restoredOrigins.addAll(
        data.cookies
            .map((cookie) => cookie['url'] as String?)
            .whereType<String>()
            .map(_normalizeOrigin)
            .whereType<String>(),
      );
    }

    if (importWebData && data.webStorage.isNotEmpty) {
      webStorageImported = await _importWebStorage(data.webStorage);
      restoredOrigins.addAll(
        data.webStorage
            .map((entry) => entry['origin'] as String?)
            .whereType<String>()
            .map(_normalizeOrigin)
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
      calculatorImported: calculatorImported,
      cookiesImported: cookiesImported,
      webStorageImported: webStorageImported,
      easyTierProfilesImported: easyTierProfilesImported,
      settingsUpdated: importSettings,
      clipboardUpdated: importClipboard,
      restoredOrigins: restoredOrigins.toList(growable: false),
    );
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

  Set<String> _collectCookieOrigins({
    required List<BrowserHistoryEntry> history,
    required List<BrowserFavorite> favorites,
    required String homepageUrl,
  }) {
    final origins = <String>{};
    for (final rawUrl in <String>{
      homepageUrl,
      ...history.map((entry) => entry.url),
      ...favorites.map((entry) => entry.url),
      ..._supplementalCookieOrigins,
    }) {
      final origin = _normalizeOrigin(rawUrl);
      if (origin != null) {
        origins.add(origin);
      }
    }
    return origins;
  }

  Set<String> _collectWebStorageOrigins({
    required List<BrowserHistoryEntry> history,
    required List<BrowserFavorite> favorites,
    required String homepageUrl,
    required List<Map<String, dynamic>> cookies,
  }) {
    final origins = <String>{};

    void addOrigin(String? rawUrl) {
      final origin = rawUrl == null ? null : _normalizeOrigin(rawUrl);
      if (origin != null) {
        origins.add(origin);
      }
    }

    for (final cookie in cookies) {
      if (_cookieSuggestsWebStorage(cookie)) {
        addOrigin(cookie['url'] as String?);
      }
    }

    return origins;
  }

  @visibleForTesting
  Set<String> collectWebStorageOriginsForTesting({
    required List<BrowserHistoryEntry> history,
    required List<BrowserFavorite> favorites,
    required String homepageUrl,
    required List<Map<String, dynamic>> cookies,
  }) {
    return _collectWebStorageOrigins(
      history: history,
      favorites: favorites,
      homepageUrl: homepageUrl,
      cookies: cookies,
    );
  }

  bool _cookieSuggestsWebStorage(Map<String, dynamic> cookie) {
    final name = cookie['name']?.toString().toLowerCase();
    if (name == null || name.isEmpty) {
      return false;
    }
    return name.contains('session');
  }

  String? _normalizeOrigin(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return uri.origin;
  }

  Future<List<Map<String, dynamic>>> _exportCookies({
    required Set<String> origins,
  }) async {
    final cookieManager = CookieManager.instance();
    final exported = <String, Map<String, dynamic>>{};

    for (final origin in origins) {
      final uri = Uri.tryParse(origin);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        continue;
      }
      try {
        final cookies = await cookieManager.getCookies(url: WebUri.uri(uri));
        for (final cookie in cookies) {
          final key = '${uri.host}|${cookie.name}|${cookie.path ?? '/'}';
          exported[key] = {
            'url': uri.origin,
            'name': cookie.name,
            'value': cookie.value,
            'domain': cookie.domain,
            'path': cookie.path,
            'expiresDate': cookie.expiresDate,
            'isSecure': cookie.isSecure,
            'isHttpOnly': cookie.isHttpOnly,
            'sameSite': cookie.sameSite?.toNativeValue(),
          };
        }
      } catch (e) {
        _logDebug('Skip cookie export for $origin: $e');
      }
    }
    return exported.values.toList();
  }

  Future<List<Map<String, dynamic>>> _exportWebStorage({
    required Set<String> origins,
  }) async {
    final exported = <Map<String, dynamic>>[];
    for (final origin in origins) {
      final snapshot = await _runWithOriginWebView<Map<String, dynamic>?>(
        origin: origin,
        task: (controller) async {
          final localStorageItems = await controller.webStorage.localStorage
              .getItems();
          final serializedItems = localStorageItems
              .where((item) => item.key != null)
              .map(
                (item) => <String, dynamic>{
                  'key': item.key,
                  'value': item.value,
                },
              )
              .toList(growable: false);
          if (serializedItems.isEmpty) {
            return null;
          }
          return <String, dynamic>{
            'origin': origin,
            'localStorage': serializedItems,
          };
        },
      );
      if (snapshot != null) {
        exported.add(snapshot);
      }
    }
    return exported;
  }

  Future<int> _importCookies(List<Map<String, dynamic>> cookies) async {
    final cookieManager = CookieManager.instance();
    var count = 0;
    for (final cookie in cookies) {
      final url = cookie['url'] as String?;
      final name = cookie['name'] as String?;
      final value = cookie['value']?.toString();
      if (url == null || name == null || value == null) {
        continue;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        continue;
      }
      try {
        await cookieManager.setCookie(
          url: WebUri.uri(uri),
          name: name,
          value: value,
          domain: cookie['domain'] as String?,
          path: cookie['path'] as String? ?? '/',
          expiresDate: (cookie['expiresDate'] as num?)?.toInt(),
          isSecure: cookie['isSecure'] as bool?,
          isHttpOnly: cookie['isHttpOnly'] as bool?,
          sameSite: _sameSiteFromValue(cookie['sameSite']),
        );
        count++;
      } catch (e) {
        _logDebug('Skip cookie import for $url/$name: $e');
      }
    }
    return count;
  }

  Future<int> _importWebStorage(List<Map<String, dynamic>> webStorage) async {
    var count = 0;
    for (final entry in webStorage) {
      final origin = entry['origin'] as String?;
      final items = (entry['localStorage'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (origin == null || items.isEmpty) {
        continue;
      }
      final restored = await _runWithOriginWebView<bool>(
        origin: origin,
        task: (controller) async {
          await controller.webStorage.localStorage.clear();
          for (final item in items) {
            final key = item['key'] as String?;
            if (key == null || key.isEmpty) {
              continue;
            }
            await controller.webStorage.localStorage.setItem(
              key: key,
              value: item['value'],
            );
          }
          return true;
        },
      );
      if (restored == true) {
        count++;
      }
    }
    return count;
  }

  Future<T?> _runWithOriginWebView<T>({
    required String origin,
    required Future<T?> Function(InAppWebViewController controller) task,
  }) async {
    final uri = Uri.tryParse(origin);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }

    final completer = Completer<T?>();
    late final HeadlessInAppWebView headlessWebView;
    var taskStarted = false;

    Future<void> complete(T? value) async {
      if (completer.isCompleted) {
        return;
      }
      completer.complete(value);
      try {
        await headlessWebView.dispose();
      } catch (_) {}
    }

    Future<void> runTask(InAppWebViewController controller) async {
      if (taskStarted || completer.isCompleted) {
        return;
      }
      taskStarted = true;
      try {
        final result = await task(controller);
        await complete(result);
      } catch (e) {
        _logDebug('Skip web storage access for $origin: $e');
        await complete(null);
      }
    }

    headlessWebView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data:
            '<!doctype html><html><head><meta charset="utf-8"></head><body></body></html>',
        baseUrl: WebUri(origin),
        historyUrl: WebUri(origin),
      ),
      onLoadStop: (controller, url) async {
        await runTask(controller);
      },
      onReceivedHttpError: (controller, request, errorResponse) async {
        if (request.isForMainFrame != false) {
          await runTask(controller);
        }
      },
      onReceivedError: (controller, request, error) async {
        if (request.isForMainFrame != false) {
          await complete(null);
        }
      },
    );

    try {
      await headlessWebView.run();
      return await completer.future.timeout(
        _webStorageExportTimeout,
        onTimeout: () => null,
      );
    } finally {
      try {
        await headlessWebView.dispose();
      } catch (_) {}
    }
  }

  HTTPCookieSameSitePolicy? _sameSiteFromValue(Object? value) {
    if (value == null) return null;
    for (final policy in HTTPCookieSameSitePolicy.values) {
      if (policy.toNativeValue() == value) {
        return policy;
      }
    }
    return null;
  }
}
