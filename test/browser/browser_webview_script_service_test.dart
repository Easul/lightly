import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/services/browser_webview_script_service.dart';

void main() {
  group('BrowserWebViewScriptService', () {
    const service = BrowserWebViewScriptService();

    test(
      'applies desktop environment script with configured user agent',
      () async {
        final scripts = <String>[];

        await service.applySiteCompatibility(
          rawUrl: 'https://example.com',
          desktopModeEnabled: true,
          desktopUserAgent: 'Custom Desktop UA',
          evaluateJavascript: (source) async => scripts.add(source),
        );

        expect(scripts, hasLength(1));
        expect(scripts.single, contains('Custom Desktop UA'));
        expect(scripts.single, contains('__lightlyApplyDesktopEnvironment'));
      },
    );

    test('applies mobile compatibility CSS only to supported sites', () async {
      final scripts = <String>[];

      await service.applySiteCompatibility(
        rawUrl: 'https://m.youtube.com/watch?v=example',
        desktopModeEnabled: false,
        desktopUserAgent: '',
        evaluateJavascript: (source) async => scripts.add(source),
      );
      await service.applySiteCompatibility(
        rawUrl: 'https://example.com',
        desktopModeEnabled: false,
        desktopUserAgent: '',
        evaluateJavascript: (source) async => scripts.add(source),
      );

      expect(scripts, hasLength(1));
      expect(scripts.single, contains('lightly-youtube-bottom-nav-fix'));
    });

    test(
      'enables and disables debug console using the requested script',
      () async {
        final scripts = <String>[];

        await service.applyWebDebugConsole(
          rawUrl: 'https://example.com',
          enabled: true,
          allowDisable: false,
          evaluateJavascript: (source) async => scripts.add(source),
        );
        await service.applyWebDebugConsole(
          rawUrl: 'https://example.com',
          enabled: false,
          allowDisable: true,
          evaluateJavascript: (source) async => scripts.add(source),
        );

        expect(scripts, hasLength(2));
        expect(scripts.first, contains('window.eruda.init'));
        expect(scripts.last, contains("return 'disabled'"));
      },
    );

    test('skips unsupported or disabled debug console requests', () async {
      final scripts = <String>[];

      await service.applyWebDebugConsole(
        rawUrl: 'file:///tmp/example.html',
        enabled: true,
        allowDisable: false,
        evaluateJavascript: (source) async => scripts.add(source),
      );
      await service.applyWebDebugConsole(
        rawUrl: 'https://example.com',
        enabled: false,
        allowDisable: false,
        evaluateJavascript: (source) async => scripts.add(source),
      );

      expect(scripts, isEmpty);
      expect(service.supportsWebDebugConsoleUrl('https://example.com'), isTrue);
      expect(service.supportsWebDebugConsoleUrl('file:///tmp/a.html'), isFalse);
    });

    test('swallows script evaluation failures', () async {
      Future<dynamic> fail(String source) async => throw StateError(source);

      await service.applySiteCompatibility(
        rawUrl: 'https://x.com',
        desktopModeEnabled: false,
        desktopUserAgent: '',
        evaluateJavascript: fail,
      );
      await service.applyWebDebugConsole(
        rawUrl: 'https://example.com',
        enabled: true,
        allowDisable: false,
        evaluateJavascript: fail,
      );
    });
  });
}
