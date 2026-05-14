import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  const BrowserSiteDataManager();

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

    await CookieManager.instance().deleteCookies(
      url: WebUri.uri(currentUri),
      domain: currentUri.host,
      path: '/',
    );
    await controller.evaluateJavascript(
      source: '''
        (() => {
          try { localStorage.clear(); } catch (_) {}
          try { sessionStorage.clear(); } catch (_) {}
          try {
            if (window.caches && caches.keys) {
              caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key))));
            }
          } catch (_) {}
          try {
            if (window.indexedDB && indexedDB.databases) {
              indexedDB.databases().then((dbs) => {
                for (const db of dbs) {
                  if (db && db.name) {
                    indexedDB.deleteDatabase(db.name);
                  }
                }
              });
            }
          } catch (_) {}
          return true;
        })();
      ''',
    );
    await controller.webStorage.localStorage.clear();
    await controller.webStorage.sessionStorage.clear();
    if (Platform.isAndroid) {
      await WebStorageManager.instance().deleteOrigin(
        origin: '${currentUri.scheme}://${currentUri.authority}',
      );
    }
    await controller.reload();
    return '已清除 ${currentUri.host} 的 Cookie 与站点数据（不含全局缓存）';
  }
}
