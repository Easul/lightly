import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_popup_raw_url_resolver.dart';

void main() {
  group('BrowserPopupRawUrlResolver', () {
    late List<Map<String, Object?>> logs;
    late List<String> debugMessages;
    late BrowserPopupRawUrlResolver resolver;

    setUp(() {
      logs = <Map<String, Object?>>[];
      debugMessages = <String>[];
      resolver = BrowserPopupRawUrlResolver(
        logWriter: (metadata) async => logs.add(metadata),
        debugWriter: debugMessages.add,
        debugLoggingEnabled: false,
      );
    });

    test('prefers bridged raw URL before evaluating page script', () async {
      const rawUrl =
          'bankabc://%7B%22method%22%3A%22jumpToSharedProduct%22%2C%22trafficTag%22%3A%2290fc%22%7D';
      resolver.recordCapturedUrl(rawUrl);
      var evaluated = false;

      final resolved = await resolver.resolve(
        fallbackUrl: rawUrl.toLowerCase(),
        evaluateJavascript: (_) async {
          evaluated = true;
          return null;
        },
      );

      expect(resolved, rawUrl);
      expect(evaluated, isFalse);
      expect(logs.single['source'], 'javascript-bridge-before-callback');
      expect(logs.single['resolvedHasCamelMethod'], isTrue);
    });

    test('uses raw URL returned by the page capture script', () async {
      const capturedUrl = 'baiduboxapp://v1/easy/bydird?upgrade=1&type=hybird';

      final resolved = await resolver.resolve(
        fallbackUrl: 'about:blank',
        evaluateJavascript: (source) async {
          expect(source, contains('__lightlyTakeRawPopupUrl'));
          return capturedUrl;
        },
      );

      expect(resolved, capturedUrl);
      expect(logs.single['source'], 'main-frame-script-queue');
    });

    test(
      'prefers a bridge delivery that arrives during script lookup',
      () async {
        const bridgedUrl = 'bankabc://rawCamelPayload';

        final resolved = await resolver.resolve(
          fallbackUrl: 'bankabc://rawcamelpayload',
          evaluateJavascript: (_) async {
            resolver.recordCapturedUrl(bridgedUrl);
            return 'bankabc://script-result';
          },
        );

        expect(resolved, bridgedUrl);
        expect(logs.single['source'], 'javascript-bridge-after-callback');
      },
    );

    test('falls back safely when script evaluation throws', () async {
      const fallbackUrl = 'customscheme://fallback';

      final resolved = await resolver.resolve(
        fallbackUrl: fallbackUrl,
        evaluateJavascript: (_) async => throw StateError('unavailable'),
      );

      expect(resolved, fallbackUrl);
      expect(
        debugMessages.single,
        contains('Failed to read captured popup URL'),
      );
      expect(logs.single['source'], 'webview-callback-fallback');
    });
  });
}
