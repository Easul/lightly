import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_webview_lifecycle_helper.dart';

void main() {
  group('BrowserPageWebViewLifecycleHelper', () {
    late BrowserPageWebViewLifecycleHelper helper;
    bool pauseTimersCalled = false;
    bool resumeTimersCalled = false;
    bool pauseWebViewCalled = false;
    bool resumeWebViewCalled = false;
    List<String> evaluatedScripts = [];
    bool trimKeepAlivesCalled = false;

    setUp(() {
      helper = const BrowserPageWebViewLifecycleHelper();
      pauseTimersCalled = false;
      resumeTimersCalled = false;
      pauseWebViewCalled = false;
      resumeWebViewCalled = false;
      evaluatedScripts = [];
      trimKeepAlivesCalled = false;
    });

    test('pauseForOverlay soft-freezes without native WebView pause', () {
      final callOrder = <String>[];

      helper.pauseForOverlay(
        pauseTimers: () {
          pauseTimersCalled = true;
          callOrder.add('pauseTimers');
        },
        pauseWebView: () {
          pauseWebViewCalled = true;
          callOrder.add('pauseWebView');
        },
        evaluateJavascript: (source) {
          evaluatedScripts.add(source);
          callOrder.add('evaluateJavascript');
        },
        trimKeepAlives: () {
          trimKeepAlivesCalled = true;
          callOrder.add('trimKeepAlives');
        },
      );

      expect(pauseTimersCalled, isFalse);
      expect(pauseWebViewCalled, isFalse);
      expect(evaluatedScripts, hasLength(1));
      expect(
        evaluatedScripts.first,
        contains('document.querySelector(\'video\')'),
      );
      expect(trimKeepAlivesCalled, isFalse);
      expect(callOrder, ['evaluateJavascript']);
    });

    test('resumeFromOverlay resumes video without native WebView resume', () {
      final callOrder = <String>[];

      helper.resumeFromOverlay(
        resumeTimers: () {
          resumeTimersCalled = true;
          callOrder.add('resumeTimers');
        },
        resumeWebView: () {
          resumeWebViewCalled = true;
          callOrder.add('resumeWebView');
        },
        evaluateJavascript: (source) {
          evaluatedScripts.add(source);
          callOrder.add('evaluateJavascript');
        },
      );

      expect(resumeTimersCalled, isFalse);
      expect(resumeWebViewCalled, isFalse);
      expect(evaluatedScripts, hasLength(1));
      expect(evaluatedScripts.first, contains('__lightlyOverlayPausedVideo'));
      expect(callOrder, ['evaluateJavascript']);
    });

    test('pauseForOverlay video script pauses playing video', () {
      helper.pauseForOverlay(
        pauseTimers: () {},
        pauseWebView: () {},
        evaluateJavascript: (source) {
          evaluatedScripts.add(source);
        },
        trimKeepAlives: () {},
      );

      expect(evaluatedScripts.first, contains('v.pause()'));
    });

    test('resumeFromOverlay video script resumes paused video', () {
      helper.resumeFromOverlay(
        resumeTimers: () {},
        resumeWebView: () {},
        evaluateJavascript: (source) {
          evaluatedScripts.add(source);
        },
      );

      expect(evaluatedScripts.first, contains('v.play()'));
    });
  });
}
