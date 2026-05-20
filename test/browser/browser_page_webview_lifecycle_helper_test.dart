import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_webview_lifecycle_helper.dart';

void main() {
  group('BrowserPageWebViewLifecycleHelper', () {
    const helper = BrowserPageWebViewLifecycleHelper();

    test('pauseForOverlay executes actions in stable order', () {
      final calls = <String>[];

      helper.pauseForOverlay(
        pauseTimers: () => calls.add('pauseTimers'),
        evaluateJavascript: (source) => calls.add('js:$source'),
        trimKeepAlives: () => calls.add('trimKeepAlives'),
      );

      expect(calls, <String>[
        'pauseTimers',
        'js:${BrowserPageWebViewLifecycleHelper.pauseVideoForOverlayScript}',
        'trimKeepAlives',
      ]);
    });

    test('resumeFromOverlay executes actions in stable order', () {
      final calls = <String>[];

      helper.resumeFromOverlay(
        resumeTimers: () => calls.add('resumeTimers'),
        evaluateJavascript: (source) => calls.add('js:$source'),
      );

      expect(calls, <String>[
        'resumeTimers',
        'js:${BrowserPageWebViewLifecycleHelper.resumeVideoFromOverlayScript}',
      ]);
    });
  });
}
