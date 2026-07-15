import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_webview_diagnostics.dart';

void main() {
  group('BrowserWebViewDiagnostics', () {
    test('logs load duration without URL query or fragment', () async {
      final entries = <Map<String, Object?>>[];
      var now = DateTime(2026, 7, 15, 12);
      final diagnostics = BrowserWebViewDiagnostics(
        now: () => now,
        logSink: (message, {error, stackTrace, metadata}) async {
          entries.add(<String, Object?>{'message': message, ...?metadata});
        },
      );

      diagnostics.recordLoadStart(
        tabId: 'tab-1',
        url: 'https://example.com/page?token=secret#fragment',
      );
      now = now.add(const Duration(seconds: 3));
      diagnostics.recordLoadStop(
        tabId: 'tab-1',
        url: 'https://example.com/page?token=secret#fragment',
      );
      await Future<void>.delayed(Duration.zero);

      expect(entries, hasLength(2));
      expect(entries.last['url'], 'https://example.com/page');
      expect(entries.last['elapsedMs'], 3000);
    });

    test('ignores subresource errors and records main frame errors', () async {
      final messages = <String>[];
      final diagnostics = BrowserWebViewDiagnostics(
        logSink: (message, {error, stackTrace, metadata}) async {
          messages.add(message);
        },
      );

      diagnostics.recordResourceError(
        tabId: 'tab-1',
        url: 'https://example.com/image.png',
        description: 'image failed',
        errorCode: -2,
        isForMainFrame: false,
      );
      diagnostics.recordResourceError(
        tabId: 'tab-1',
        url: 'https://example.com',
        description: 'page failed',
        errorCode: -2,
        isForMainFrame: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(messages, <String>['Browser WebView resource error']);
    });

    test('redacts non web URL payloads', () {
      final diagnostics = BrowserWebViewDiagnostics(
        logSink: (message, {error, stackTrace, metadata}) async {},
      );

      expect(
        diagnostics.safeUrl('bankabc://%7B%22token%22%3A%22secret%22%7D'),
        'bankabc://',
      );
    });
  });
}
