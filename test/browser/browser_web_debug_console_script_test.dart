import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/utils/browser_web_debug_console_script.dart';

void main() {
  group('BrowserWebDebugConsoleScript', () {
    test('supports only http and https urls', () {
      expect(
        BrowserWebDebugConsoleScript.supportsUrl('https://example.com'),
        isTrue,
      );
      expect(
        BrowserWebDebugConsoleScript.supportsUrl('http://example.com'),
        isTrue,
      );
      expect(
        BrowserWebDebugConsoleScript.supportsUrl('file:///tmp/a.html'),
        isFalse,
      );
      expect(BrowserWebDebugConsoleScript.supportsUrl('about:blank'), isFalse);
      expect(BrowserWebDebugConsoleScript.supportsUrl(null), isFalse);
    });

    test('enable script references eruda cdn fallbacks', () {
      final script = BrowserWebDebugConsoleScript.buildEnableScript();

      expect(script, contains('cdn.jsdelivr.net'));
      expect(script, contains('unpkg.com/eruda'));
      expect(script, contains('window.eruda.init'));
    });

    test('disable script tears down eruda state', () {
      final script = BrowserWebDebugConsoleScript.buildDisableScript();

      expect(script, contains('window.eruda.destroy'));
      expect(script, contains('lightly-eruda-script'));
    });
  });
}
