import 'package:flutter/material.dart';

import '../../features/video/application/browser_video_detection_tracker.dart';
import '../../features/video/application/video_playback_preparer.dart';
import '../../features/video/domain/floating_video_system_ui_runtime.dart';
import '../../features/video/presentation/floating_video_player_coordinator.dart';
import '../../features/video/presentation/widgets/floating_video_player.dart';
import '../browser_settings.dart';
import 'browser_download_coordinator.dart';
import 'browser_floating_video_download_runtime.dart';

class BrowserVideoPlayerCoordinator {
  BrowserVideoPlayerCoordinator({
    required VideoPlaybackPreparer playbackPreparationService,
    required BrowserDownloadCoordinator downloadCoordinator,
    required BrowserVideoDetectionTracker videoDetectionTracker,
    required Future<void> Function() stopProxyServer,
    required void Function(String) onShowSnackBar,
    required void Function(String) onDebugLog,
    required FloatingVideoSystemUiRuntime floatingVideoSystemUiRuntime,
  }) : _delegate = FloatingVideoPlayerCoordinator<BrowserSettings>(
         playbackPreparationService: playbackPreparationService,
         downloadRuntime: BrowserFloatingVideoDownloadRuntime(
           downloadCoordinator: downloadCoordinator,
         ),
         videoDetectionTracker: videoDetectionTracker,
         stopProxyServer: stopProxyServer,
         onShowSnackBar: onShowSnackBar,
         onDebugLog: onDebugLog,
         floatingVideoSystemUiRuntime: floatingVideoSystemUiRuntime,
       );

  final FloatingVideoPlayerCoordinator<BrowserSettings> _delegate;

  OverlayEntry? get floatingVideoOverlay => _delegate.floatingVideoOverlay;

  FloatingVideoPlayerController get floatingVideoPlayerController =>
      _delegate.floatingVideoPlayerController;

  bool get hasActiveOverlay => _delegate.hasActiveOverlay;

  bool get isLooping => _delegate.isLooping;

  bool shouldOpenNativeVideoFromUrl(String url, BrowserSettings settings) {
    return settings.canResolveYoutubeWithNativePlayer &&
        _delegate.supportsResolvedPlayback(url);
  }

  Future<void> showFloatingVideoPlayer({
    required BuildContext context,
    required String url,
    required BrowserSettings settings,
    required String currentPageTitle,
  }) {
    return _delegate.showFloatingVideoPlayer(
      context: context,
      url: url,
      shouldResolveYoutube: shouldOpenNativeVideoFromUrl(url, settings),
      downloadContext: settings,
      currentPageTitle: currentPageTitle,
    );
  }

  Future<void> closeFloatingVideoPlayer() =>
      _delegate.closeFloatingVideoPlayer();

  Future<void> dispose() => _delegate.dispose();
}
