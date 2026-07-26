import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_download_request_context_resolver.dart';

void main() {
  group('BrowserDownloadRequestContextResolver', () {
    test('forwards webview cookie user agent and sanitized referrer', () async {
      WebUri? cookieLookupUrl;
      final resolver = BrowserDownloadRequestContextResolver(
        cookieHeaderLoader: (url) async {
          cookieLookupUrl = url;
          return 'accountToken=secret; websiteToken=token';
        },
      );

      final headers = await resolver.resolve(
        url: WebUri('https://store8.gofile.io/download/file.apk'),
        userAgent: ' WebView UA ',
        referrerUrl: 'https://gofile.io/d/content-id?private=token#download',
      );

      expect(
        cookieLookupUrl.toString(),
        'https://store8.gofile.io/download/file.apk',
      );
      expect(headers[HttpHeaders.userAgentHeader], 'WebView UA');
      expect(
        headers[HttpHeaders.cookieHeader],
        'accountToken=secret; websiteToken=token',
      );
      expect(
        headers[HttpHeaders.refererHeader],
        'https://gofile.io/d/content-id',
      );
    });

    test('keeps safe headers when cookie lookup fails', () async {
      final resolver = BrowserDownloadRequestContextResolver(
        cookieHeaderLoader: (_) async => throw StateError('unavailable'),
      );

      final headers = await resolver.resolve(
        url: WebUri('https://example.com/file.bin'),
        userAgent: 'WebView UA',
        referrerUrl: 'intent://private-payload',
      );

      expect(headers, <String, String>{
        HttpHeaders.userAgentHeader: 'WebView UA',
      });
    });
  });
}
