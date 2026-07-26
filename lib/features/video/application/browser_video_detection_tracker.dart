import '../domain/youtube_long_press_utils.dart';

class BrowserVideoDetectionTracker {
  final Set<String> _promptedUrls = <String>{};
  final Map<String, DateTime> _recentlyDismissedUrls = <String, DateTime>{};

  bool isProcessing = false;
  String? activeUrl;

  static const Duration dismissalWindow = Duration(seconds: 12);

  String normalizeUrl(String url) {
    final trimmed = url.trim();
    final youtubeTargets = deriveYouTubeLongPressTargets(trimmed);
    if (youtubeTargets != null) {
      return youtubeTargets.desktopWatchUrl;
    }
    return trimmed;
  }

  void setActiveUrl(String url) {
    activeUrl = normalizeUrl(url);
  }

  void clearPromptState() {
    _promptedUrls.clear();
    isProcessing = false;
  }

  void reset() {
    _promptedUrls.clear();
    _recentlyDismissedUrls.clear();
    activeUrl = null;
    isProcessing = false;
  }

  void rememberDismissedUrl(String? url, {DateTime Function()? now}) {
    if (url == null || url.isEmpty) {
      return;
    }
    _recentlyDismissedUrls[normalizeUrl(url)] = (now ?? DateTime.now)();
  }

  bool wasRecentlyDismissed(String url, {DateTime Function()? now}) {
    final normalizedUrl = normalizeUrl(url);
    final dismissedAt = _recentlyDismissedUrls[normalizedUrl];
    if (dismissedAt == null) {
      return false;
    }
    if ((now ?? DateTime.now)().difference(dismissedAt) > dismissalWindow) {
      _recentlyDismissedUrls.remove(normalizedUrl);
      return false;
    }
    return true;
  }

  bool shouldSkipDetectedUrl(String? url, {required bool nativeVideoEnabled}) {
    if (url == null || url.isEmpty || !nativeVideoEnabled) {
      return true;
    }

    final normalizedUrl = normalizeUrl(url);
    if (_promptedUrls.contains(normalizedUrl)) {
      return true;
    }
    if (normalizedUrl.startsWith('blob:') ||
        normalizedUrl.startsWith('data:')) {
      return true;
    }
    if (wasRecentlyDismissed(normalizedUrl)) {
      return true;
    }
    if (isProcessing) {
      return true;
    }
    return false;
  }

  String markDetectionStarted(String url) {
    final normalizedUrl = normalizeUrl(url);
    _promptedUrls.add(normalizedUrl);
    isProcessing = true;
    return normalizedUrl;
  }
}
