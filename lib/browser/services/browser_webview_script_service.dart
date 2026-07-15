import '../utils/browser_site_compatibility_script.dart';
import '../utils/browser_web_debug_console_script.dart';

typedef BrowserWebViewJavascriptEvaluator =
    Future<dynamic> Function(String source);

class BrowserWebViewScriptService {
  const BrowserWebViewScriptService();

  Future<void> applySiteCompatibility({
    required String? rawUrl,
    required bool desktopModeEnabled,
    required String desktopUserAgent,
    required BrowserWebViewJavascriptEvaluator evaluateJavascript,
  }) async {
    final script = desktopModeEnabled
        ? BrowserSiteCompatibilityScript.desktopViewportOverrideForUrl(
            rawUrl,
            desktopUserAgent: desktopUserAgent,
          )
        : BrowserSiteCompatibilityScript.bottomNavigationFixForUrl(rawUrl);
    if (script == null) {
      return;
    }
    try {
      await evaluateJavascript(script);
    } catch (_) {
      // Best-effort compatibility scripts must not interrupt navigation.
    }
  }

  bool supportsWebDebugConsoleUrl(String? rawUrl) {
    return BrowserWebDebugConsoleScript.supportsUrl(rawUrl);
  }

  Future<void> applyWebDebugConsole({
    required String? rawUrl,
    required bool enabled,
    required bool allowDisable,
    required BrowserWebViewJavascriptEvaluator evaluateJavascript,
  }) async {
    if (!supportsWebDebugConsoleUrl(rawUrl)) {
      return;
    }
    if (!enabled && !allowDisable) {
      return;
    }
    final script = enabled
        ? BrowserWebDebugConsoleScript.buildEnableScript()
        : BrowserWebDebugConsoleScript.buildDisableScript();
    try {
      await evaluateJavascript(script);
    } catch (_) {
      // Keep page loading resilient when late script execution is rejected.
    }
  }
}
