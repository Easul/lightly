class BrowserPageWebViewLifecycleHelper {
  const BrowserPageWebViewLifecycleHelper();

  static const String pauseVideoForOverlayScript =
      "var v=document.querySelector('video'); if(v&&!v.paused){v.pause();window.__lightlyOverlayPausedVideo=true;}";

  static const String resumeVideoFromOverlayScript =
      "if(window.__lightlyOverlayPausedVideo){var v=document.querySelector('video'); if(v)v.play();window.__lightlyOverlayPausedVideo=false;}";

  void pauseForOverlay({
    required void Function() pauseTimers,
    required void Function() pauseWebView,
    required void Function(String source) evaluateJavascript,
    required void Function() trimKeepAlives,
  }) {
    // Keep the Android WebView renderer attached and running while overlays
    // animate. Native pause()/pauseTimers() can restore as a blank platform
    // view with retained keepAlive WebViews, especially after a tab has been in
    // the background for a while. BrowserPage still freezes user interaction
    // with IgnorePointer and defers parent rebuilds during the overlay. Do not
    // trim retained tab WebViews here; tab-preserving overlays should not race
    // native WebView disposal against platform-view attach/restore.
    evaluateJavascript(pauseVideoForOverlayScript);
  }

  void resumeFromOverlay({
    required void Function() resumeTimers,
    required void Function() resumeWebView,
    required void Function(String source) evaluateJavascript,
  }) {
    evaluateJavascript(resumeVideoFromOverlayScript);
  }
}
