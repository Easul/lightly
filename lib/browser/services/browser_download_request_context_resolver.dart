import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef BrowserDownloadCookieHeaderLoader =
    Future<String?> Function(WebUri url);

class BrowserDownloadRequestContextResolver {
  BrowserDownloadRequestContextResolver({
    BrowserDownloadCookieHeaderLoader? cookieHeaderLoader,
  }) : _cookieHeaderLoader = cookieHeaderLoader ?? _loadWebViewCookieHeader;

  final BrowserDownloadCookieHeaderLoader _cookieHeaderLoader;

  Future<Map<String, String>> resolve({
    required WebUri url,
    String? userAgent,
    String? referrerUrl,
  }) async {
    final headers = <String, String>{};
    final normalizedUserAgent = userAgent?.trim();
    if (normalizedUserAgent != null && normalizedUserAgent.isNotEmpty) {
      headers[HttpHeaders.userAgentHeader] = normalizedUserAgent;
    }

    final referrer = _normalizeReferrer(referrerUrl);
    if (referrer != null) {
      headers[HttpHeaders.refererHeader] = referrer;
    }

    try {
      final cookieHeader = (await _cookieHeaderLoader(url))?.trim();
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        headers[HttpHeaders.cookieHeader] = cookieHeader;
      }
    } catch (_) {}

    return Map<String, String>.unmodifiable(headers);
  }

  static Future<String?> _loadWebViewCookieHeader(WebUri url) async {
    final cookies = await CookieManager.instance().getCookies(url: url);
    final entries = cookies
        .where((cookie) => cookie.name.trim().isNotEmpty)
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .toList(growable: false);
    return entries.isEmpty ? null : entries.join('; ');
  }

  static String? _normalizeReferrer(String? rawUrl) {
    final value = rawUrl?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}
