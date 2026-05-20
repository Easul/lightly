class BrowserPageWebViewLifecycleHelper {
  const BrowserPageWebViewLifecycleHelper();

  static const String pauseVideoForOverlayScript =
      "var v=document.querySelector('video'); if(v&&!v.paused){v.pause();window.__lightlyOverlayPausedVideo=true;}";

  static const String resumeVideoFromOverlayScript =
      "if(window.__lightlyOverlayPausedVideo){var v=document.querySelector('video'); if(v)v.play();window.__lightlyOverlayPausedVideo=false;}";

  void pauseForOverlay({
    required void Function() pauseTimers,
    required void Function(String source) evaluateJavascript,
    required void Function() trimKeepAlives,
  }) {
    pauseTimers();
    evaluateJavascript(pauseVideoForOverlayScript);
    trimKeepAlives();
  }

  void resumeFromOverlay({
    required void Function() resumeTimers,
    required void Function(String source) evaluateJavascript,
  }) {
    resumeTimers();
    evaluateJavascript(resumeVideoFromOverlayScript);
  }
}
