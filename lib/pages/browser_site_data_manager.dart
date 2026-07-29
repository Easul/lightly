import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../browser/services/browser_cookie_origin_service.dart';

class BrowserSiteCookieDeletion {
  const BrowserSiteCookieDeletion({
    required this.url,
    required this.name,
    required this.domain,
    required this.path,
  });

  final Uri url;
  final String name;
  final String? domain;
  final String path;

  String get key => '${url.origin}\u0000$name\u0000${domain ?? ''}\u0000$path';
}

class BrowserSiteCookiePolicy {
  const BrowserSiteCookiePolicy();

  List<Uri> lookupUris(Uri currentUri) {
    final schemes = <String>{currentUri.scheme, 'https', 'http'};
    final paths = <String>{
      currentUri.path.isEmpty ? '/' : currentUri.path,
      '/',
    };
    return [
      for (final scheme in schemes)
        for (final path in paths)
          Uri(scheme: scheme, host: currentUri.host, path: path),
    ];
  }

  List<BrowserSiteCookieDeletion> deletionCandidates({
    required Uri currentUri,
    required Iterable<Cookie> cookies,
  }) {
    final candidates = <String, BrowserSiteCookieDeletion>{};
    final fallbackDomains = _fallbackDomains(currentUri.host);
    final fallbackPaths = _fallbackPaths(currentUri.path);

    void add(String name, String? domain, String path) {
      final candidate = BrowserSiteCookieDeletion(
        url: currentUri,
        name: name,
        domain: domain,
        path: path.isEmpty ? '/' : path,
      );
      candidates[candidate.key] = candidate;
    }

    for (final cookie in cookies) {
      final domain = cookie.domain?.trim();
      final path = cookie.path?.trim();
      if (domain != null &&
          domain.isNotEmpty &&
          path != null &&
          path.isNotEmpty) {
        add(cookie.name, domain, path);
        continue;
      }

      final domains = domain != null && domain.isNotEmpty
          ? <String?>{domain}
          : fallbackDomains;
      final paths = path != null && path.isNotEmpty
          ? <String>{path}
          : fallbackPaths;
      for (final fallbackDomain in domains) {
        for (final fallbackPath in paths) {
          add(cookie.name, fallbackDomain, fallbackPath);
        }
      }
    }
    return candidates.values.toList(growable: false);
  }

  Set<String> cookieSiteDomains({
    required String currentHost,
    required Iterable<Cookie> cookies,
  }) {
    final normalizedHost = currentHost.toLowerCase();
    return cookies
        .map((cookie) => cookie.domain?.trim().toLowerCase())
        .whereType<String>()
        .map((domain) => domain.startsWith('.') ? domain.substring(1) : domain)
        .where(
          (domain) =>
              domain.isNotEmpty &&
              (normalizedHost == domain || normalizedHost.endsWith('.$domain')),
        )
        .toSet();
  }

  List<Uri> relatedOrigins({
    required Uri currentUri,
    required Iterable<String> recordedOrigins,
    required Set<String> cookieSiteDomains,
  }) {
    final origins = <String, Uri>{currentUri.origin: currentUri};
    for (final rawOrigin in recordedOrigins) {
      final uri = Uri.tryParse(rawOrigin);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        continue;
      }
      final host = uri.host.toLowerCase();
      if (cookieSiteDomains.any(
        (domain) => host == domain || host.endsWith('.$domain'),
      )) {
        origins[uri.origin] = uri;
      }
    }
    return origins.values.toList(growable: false);
  }

  Set<String?> _fallbackDomains(String host) {
    final labels = host.split('.').where((label) => label.isNotEmpty).toList();
    final domains = <String?>{null, host};
    for (var index = 1; index < labels.length - 1; index++) {
      final domain = labels.sublist(index).join('.');
      domains
        ..add(domain)
        ..add('.$domain');
    }
    return domains;
  }

  Set<String> _fallbackPaths(String currentPath) {
    final paths = <String>{'/'};
    final segments = currentPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    for (var length = 1; length <= segments.length; length++) {
      paths.add('/${segments.take(length).join('/')}/');
    }
    if (currentPath.isNotEmpty) {
      paths.add(currentPath.startsWith('/') ? currentPath : '/$currentPath');
    }
    return paths;
  }
}

class BrowserSiteSecurityState {
  const BrowserSiteSecurityState({
    required this.title,
    required this.hostLabel,
    required this.description,
    required this.canManageSiteData,
  });

  final String title;
  final String hostLabel;
  final String description;
  final bool canManageSiteData;
}

class BrowserSiteDataException implements Exception {
  const BrowserSiteDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BrowserSiteDataManager {
  BrowserSiteDataManager({
    BrowserSiteCookiePolicy cookiePolicy = const BrowserSiteCookiePolicy(),
    BrowserCookieOriginService? cookieOriginService,
  }) : _cookiePolicy = cookiePolicy,
       _cookieOriginService =
           cookieOriginService ?? BrowserCookieOriginService();

  final BrowserSiteCookiePolicy _cookiePolicy;
  final BrowserCookieOriginService _cookieOriginService;

  bool isWebSite(Uri? currentUri) {
    return currentUri != null &&
        currentUri.hasScheme &&
        currentUri.host.isNotEmpty &&
        (currentUri.scheme == 'http' || currentUri.scheme == 'https');
  }

  BrowserSiteSecurityState buildSecurityState({
    required Uri? currentUri,
    required bool isSecure,
  }) {
    final webSite = isWebSite(currentUri);
    return BrowserSiteSecurityState(
      title: isSecure ? '安全连接' : '站点信息',
      hostLabel: webSite ? currentUri!.host : '当前页面没有可管理的站点数据',
      description: webSite
          ? '可清除当前网站的 Cookie 和页面本地存储。WebView 的底层 HTTP 缓存仍是全局能力，不能只删单站点。'
          : '仅 http/https 网站支持该操作。',
      canManageSiteData: webSite,
    );
  }

  Future<String> clearCurrentSiteData({
    required Uri currentUri,
    required InAppWebViewController? controller,
  }) async {
    if (controller == null) {
      throw const BrowserSiteDataException('当前页面尚未准备好');
    }

    final cookieManager = CookieManager.instance();
    final cookiesByOrigin = <String, Map<String, Cookie>>{};

    Future<void> collectCookies(Uri uri) async {
      final originCookies = cookiesByOrigin.putIfAbsent(
        uri.origin,
        () => <String, Cookie>{},
      );
      for (final lookupUri in _cookiePolicy.lookupUris(uri)) {
        for (final cookie in await cookieManager.getCookies(
          url: WebUri.uri(lookupUri),
        )) {
          final key =
              '${cookie.name}\u0000${cookie.domain ?? ''}\u0000'
              '${cookie.path ?? ''}\u0000${cookie.value}';
          originCookies[key] = cookie;
        }
      }
    }

    await collectCookies(currentUri);
    final currentCookies = cookiesByOrigin[currentUri.origin]!.values;
    final cookieSiteDomains = _cookiePolicy.cookieSiteDomains(
      currentHost: currentUri.host,
      cookies: currentCookies,
    );
    final relatedOrigins = _cookiePolicy.relatedOrigins(
      currentUri: currentUri,
      recordedOrigins: await _cookieOriginService.loadOrigins(),
      cookieSiteDomains: cookieSiteDomains,
    );
    for (final origin in relatedOrigins) {
      if (origin.origin != currentUri.origin) {
        await collectCookies(origin);
      }
    }

    final cookieDeletions = <String, BrowserSiteCookieDeletion>{};
    for (final origin in relatedOrigins) {
      final cookies =
          cookiesByOrigin[origin.origin]?.values ?? const <Cookie>[];
      for (final deletion in _cookiePolicy.deletionCandidates(
        currentUri: origin,
        cookies: cookies,
      )) {
        cookieDeletions[deletion.key] = deletion;
      }
    }
    for (final deletion in cookieDeletions.values) {
      await cookieManager.deleteCookie(
        url: WebUri.uri(deletion.url),
        name: deletion.name,
        domain: deletion.domain,
        path: deletion.path,
      );
    }
    await controller.callAsyncJavaScript(
      functionBody: '''
        try { localStorage.clear(); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
        try {
          if (window.caches && caches.keys) {
            const keys = await caches.keys();
            await Promise.all(keys.map((key) => caches.delete(key)));
          }
        } catch (_) {}
        try {
          if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
            const registrations = await navigator.serviceWorker.getRegistrations();
            await Promise.all(registrations.map((registration) => registration.unregister()));
          }
        } catch (_) {}
        try {
          if (window.indexedDB && indexedDB.databases) {
            const databases = await indexedDB.databases();
            await Promise.all(databases
              .filter((database) => database && database.name)
              .map((database) => new Promise((resolve) => {
                const request = indexedDB.deleteDatabase(database.name);
                request.onsuccess = resolve;
                request.onerror = resolve;
                request.onblocked = resolve;
              })));
          }
        } catch (_) {}
        return true;
      ''',
    );
    await controller.webStorage.localStorage.clear();
    await controller.webStorage.sessionStorage.clear();
    if (Platform.isAndroid) {
      for (final origin in relatedOrigins) {
        await WebStorageManager.instance().deleteOrigin(origin: origin.origin);
      }
    }
    await controller.reload();
    return '已清除 ${currentUri.host} 的 Cookie 与站点数据（不含全局缓存）';
  }
}
