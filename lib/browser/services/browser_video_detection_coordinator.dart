import 'dart:async';

import 'browser_video_detection_tracker.dart';

class BrowserVideoDetectionCoordinator {
  BrowserVideoDetectionCoordinator({
    required BrowserVideoDetectionTracker tracker,
  }) : _tracker = tracker;

  final BrowserVideoDetectionTracker _tracker;

  bool _videoScriptInjected = false;

  bool get isVideoScriptInjected => _videoScriptInjected;

  void clearPromptStateForSettingsChange() {
    _videoScriptInjected = false;
    _tracker.clearPromptState();
  }

  void resetAll() {
    _videoScriptInjected = false;
    _tracker.reset();
  }

  bool shouldInjectScript({required bool nativeVideoEnabled}) {
    return nativeVideoEnabled && !_videoScriptInjected;
  }

  void markScriptInjected() {
    _videoScriptInjected = true;
  }

  Future<void> handleDetectedVideo(
    String? url, {
    required bool nativeVideoEnabled,
    required Future<void> Function(String normalizedUrl) onOpenVideo,
  }) async {
    if (_tracker.shouldSkipDetectedUrl(
      url,
      nativeVideoEnabled: nativeVideoEnabled,
    )) {
      return;
    }

    final normalizedUrl = _tracker.markDetectionStarted(url!);

    try {
      await onOpenVideo(normalizedUrl);
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _tracker.isProcessing = false;
      });
    }
  }

  String buildInjectionScript() {
    return r'''
(function() {
  if (window.__nativeVideoHookInstalled) return;
  window.__nativeVideoHookInstalled = true;

  var isYouTubeHost = /(^|\.)youtube\.com$/i.test(location.hostname) ||
                      /(^|\.)youtu\.be$/i.test(location.hostname);

  function getYoutubeVideoId() {
    var match = location.href.match(/[?&]v=([^&]+)/);
    if (match) return match[1];
    match = location.href.match(/\/shorts\/([^?/]+)/);
    if (match) return match[1];
    match = location.href.match(/\/embed\/([^?/]+)/);
    if (match) return match[1];
    return null;
  }

  var reportedUrls = new Set();
  var reportTimer = null;

  function reportVideo() {
    var youtubeId = getYoutubeVideoId();
    if (youtubeId && window.flutter_inappwebview) {
      var url = 'https://www.youtube.com/watch?v=' + youtubeId;
      if (!reportedUrls.has(url)) {
        reportedUrls.add(url);
        window.flutter_inappwebview.callHandler('onVideoDetected', url);
      }
      return;
    }

    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      var v = videos[i];
      var src = v.currentSrc || v.src || '';
      if (!src) {
        var sources = v.querySelectorAll('source');
        for (var j = 0; j < sources.length; j++) {
          if (sources[j].src) {
            src = sources[j].src;
            break;
          }
        }
      }
      if (src && !src.startsWith('blob:') && !src.startsWith('data:') && window.flutter_inappwebview && !reportedUrls.has(src)) {
        reportedUrls.add(src);
        window.flutter_inappwebview.callHandler('onVideoDetected', src);
      }
    }
  }

  function scheduleReport() {
    if (reportTimer) {
      clearTimeout(reportTimer);
    }
    reportTimer = setTimeout(function() {
      reportTimer = null;
      reportVideo();
    }, isYouTubeHost ? 700 : 450);
  }

  reportVideo();

  if (isYouTubeHost) {
    window.addEventListener('yt-navigate-finish', scheduleReport, true);
    window.addEventListener('popstate', scheduleReport, true);
    window.addEventListener('hashchange', scheduleReport, true);
  } else {
    var observer = new MutationObserver(function(mutations) {
      var hasVideo = false;
      for (var i = 0; i < mutations.length; i++) {
        var nodes = mutations[i].addedNodes;
        for (var j = 0; j < nodes.length; j++) {
          var node = nodes[j];
          if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE') {
            hasVideo = true;
            break;
          }
          if (node.querySelector && node.querySelector('video, source')) {
            hasVideo = true;
            break;
          }
        }
        if (hasVideo) break;
      }
      if (hasVideo) {
        scheduleReport();
      }
    });

    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
    }
  }

  document.addEventListener('play', function(e) {
    if (e.target.tagName === 'VIDEO') {
      scheduleReport();
    }
  }, true);
})();
''';
  }
}
