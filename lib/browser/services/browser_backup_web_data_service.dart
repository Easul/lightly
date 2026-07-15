import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/browser_favorite.dart';
import '../models/browser_history_entry.dart';
import 'browser_cookie_origin_service.dart';

typedef BrowserBackupLogSink =
    void Function(
      String message, {
      Object? error,
      Map<String, Object?>? metadata,
    });

class BrowserBackupWebDataService {
  BrowserBackupWebDataService({
    required BrowserCookieOriginService cookieOriginService,
    required BrowserBackupLogSink logDebug,
  }) : _cookieOriginService = cookieOriginService,
       _logDebug = logDebug;

  static const Set<String> _supplementalCookieOrigins = <String>{
    'https://hax.co.id',
    'https://oauth.telegram.org',
    'https://www.duckcoding.ai',
    'https://muyuan.do',
    'https://new-api.abrdns.com',
    'https://accounts.google.com',
    'https://login.microsoftonline.com',
    'https://appleid.apple.com',
  };
  static const Set<String> _supplementalWebStorageOrigins = <String>{
    'https://www.duckcoding.ai',
    'https://muyuan.do',
    'https://new-api.abrdns.com',
    'https://free.linggan10s.shop',
    'https://up.x666.me',
  };
  static const Duration _webStorageExportTimeout = Duration(seconds: 4);

  final BrowserCookieOriginService _cookieOriginService;
  final BrowserBackupLogSink _logDebug;

  Future<Set<String>> collectCookieUrls() async {
    final urls = <String>{};
    final recordedOrigins = await _cookieOriginService.loadOrigins();
    for (final rawUrl in <String>{
      ...recordedOrigins,
      ..._supplementalCookieOrigins,
    }) {
      final cookieUrl = normalizeCookieLookupUrl(rawUrl);
      if (cookieUrl != null) {
        urls.add(cookieUrl);
      }
    }
    return urls;
  }

  Set<String> collectWebStorageOrigins({
    required List<BrowserHistoryEntry> history,
    required List<BrowserFavorite> favorites,
    required String homepageUrl,
    required List<Map<String, dynamic>> cookies,
  }) {
    final origins = <String>{};

    void addOrigin(String? rawUrl) {
      final origin = rawUrl == null ? null : normalizeOrigin(rawUrl);
      if (origin != null) {
        origins.add(origin);
      }
    }

    for (final cookie in cookies) {
      if (_cookieSuggestsWebStorage(cookie)) {
        addOrigin(cookie['url'] as String?);
      }
    }

    for (final origin in _supplementalWebStorageOrigins) {
      addOrigin(origin);
    }

    return origins;
  }

  String? normalizeOrigin(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return uri.origin;
  }

  String? normalizeCookieLookupUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  Future<List<Map<String, dynamic>>> exportCookies({
    required Set<String> urls,
  }) async {
    final cookieManager = CookieManager.instance();
    final exported = <String, Map<String, dynamic>>{};

    for (final lookupUrl in urls) {
      final uri = Uri.tryParse(lookupUrl);
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
        _logDebug(
          'Cookie export skipped',
          error: e,
          metadata: <String, Object?>{'origin': uri.origin},
        );
      }
    }
    return exported.values.toList();
  }

  Future<List<Map<String, dynamic>>> exportWebStorage({
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

  Future<int> importCookies(List<Map<String, dynamic>> cookies) async {
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
        _logDebug(
          'Cookie import skipped',
          error: e,
          metadata: <String, Object?>{'origin': uri.origin},
        );
      }
    }
    return count;
  }

  Future<int> importWebStorage(List<Map<String, dynamic>> webStorage) async {
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

  bool _cookieSuggestsWebStorage(Map<String, dynamic> cookie) {
    final name = cookie['name']?.toString().toLowerCase();
    if (name == null || name.isEmpty) {
      return false;
    }
    return name.contains('session') || name.contains('linuxdo_oauth_intent');
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
        _logDebug(
          'Web storage access skipped',
          error: e,
          metadata: <String, Object?>{'origin': uri.origin},
        );
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
