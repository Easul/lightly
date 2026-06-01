import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../browser_settings.dart';
import '../utils/youtube_long_press_utils.dart';
import '../widgets/floating_video_player.dart';
import 'browser_download_coordinator.dart';
import 'browser_video_detection_tracker.dart';
import 'browser_video_playback_preparation_service.dart';

class BrowserVideoPlayerCoordinator {
  BrowserVideoPlayerCoordinator({
    required BrowserVideoPlaybackPreparationService playbackPreparationService,
    required BrowserDownloadCoordinator downloadCoordinator,
    required BrowserVideoDetectionTracker videoDetectionTracker,
    required Future<void> Function() stopProxyServer,
    required void Function(String) onShowSnackBar,
    required void Function(String) onDebugLog,
  }) : _playbackPreparationService = playbackPreparationService,
       _downloadCoordinator = downloadCoordinator,
       _videoDetectionTracker = videoDetectionTracker,
       _stopProxyServer = stopProxyServer,
       _onShowSnackBar = onShowSnackBar,
       _onDebugLog = onDebugLog;

  final BrowserVideoPlaybackPreparationService _playbackPreparationService;
  final BrowserDownloadCoordinator _downloadCoordinator;
  final BrowserVideoDetectionTracker _videoDetectionTracker;
  final Future<void> Function() _stopProxyServer;
  final void Function(String) _onShowSnackBar;
  final void Function(String) _onDebugLog;

  OverlayEntry? _floatingVideoOverlay;
  VideoPlayerController? _floatingVideoController;
  final FloatingVideoPlayerController _floatingVideoPlayerController =
      FloatingVideoPlayerController();

  OverlayEntry? get floatingVideoOverlay => _floatingVideoOverlay;
  FloatingVideoPlayerController get floatingVideoPlayerController =>
      _floatingVideoPlayerController;
  bool get hasActiveOverlay => _floatingVideoOverlay != null;

  bool shouldOpenNativeVideoFromUrl(String url, BrowserSettings settings) {
    return settings.canResolveYoutubeWithNativePlayer &&
        deriveYouTubeLongPressTargets(url) != null;
  }

  static String? _normalizeFloatingTitle(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalized =
        BrowserDownloadCoordinator.normalizeFloatingDownloadTitle(trimmed);
    return normalized?.trim().isNotEmpty == true ? normalized : null;
  }

  Future<void> showFloatingVideoPlayer({
    required BuildContext context,
    required String url,
    required BrowserSettings settings,
    required String currentPageTitle,
  }) async {
    await closeFloatingVideoPlayer();
    if (!context.mounted) {
      return;
    }
    _videoDetectionTracker.setActiveUrl(url);
    final pageTitle = _normalizeFloatingTitle(currentPageTitle);
    var floatingTitle = pageTitle ?? '视频播放';

    _floatingVideoOverlay = FloatingVideoPlayer.show(
      context: context,
      isLoading: true,
      title: floatingTitle,
      onClose: () {
        unawaited(closeFloatingVideoPlayer());
      },
      playerController: _floatingVideoPlayerController,
    );

    var playbackUrl = url;
    var downloadUrl = url;
    var displayDownloadUrl = BrowserDownloadCoordinator.redactDownloadUrl(url);
    String? suggestedDownloadFileName;
    final shouldResolveYoutube = shouldOpenNativeVideoFromUrl(url, settings);

    try {
      final preparedPlayback = await _playbackPreparationService.prepare(
        requestedUrl: url,
        shouldResolveYoutube: shouldResolveYoutube,
      );
      playbackUrl = preparedPlayback.playbackUrl;
      downloadUrl = preparedPlayback.downloadUrl;
      displayDownloadUrl = preparedPlayback.displayDownloadUrl;

      if (shouldResolveYoutube) {
        floatingTitle =
            _normalizeFloatingTitle(preparedPlayback.resolvedTitle) ??
            pageTitle ??
            '视频播放';
        suggestedDownloadFileName = _downloadCoordinator
            .resolveFloatingDownloadFileName(
              downloadUrl,
              pageTitle: floatingTitle,
            );
      }
    } catch (error) {
      if (shouldResolveYoutube) {
        _onDebugLog('Failed to resolve YouTube video: $error');
        if (!context.mounted) {
          await closeFloatingVideoPlayer();
          return;
        }
        _showFloatingErrorOverlay(
          context: context,
          title: floatingTitle,
          message: '视频解析失败: $error',
          onDownload: suggestedDownloadFileName == null
              ? null
              : () {
                  unawaited(
                    _downloadVideo(
                      context,
                      settings,
                      downloadUrl,
                      displayUrl: displayDownloadUrl,
                      suggestedFileName: suggestedDownloadFileName,
                    ),
                  );
                },
        );
        return;
      }
    }

    final controller = _createVideoController(playbackUrl);
    _floatingVideoController = controller;

    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!context.mounted) {
        await controller.dispose();
        _floatingVideoController = null;
        await closeFloatingVideoPlayer();
        return;
      }

      controller.play();

      _floatingVideoOverlay?.remove();
      _floatingVideoOverlay = FloatingVideoPlayer.show(
        context: context,
        controller: controller,
        title: floatingTitle,
        onClose: () {
          unawaited(closeFloatingVideoPlayer());
        },
        onDownload: () {
          unawaited(
            _downloadVideo(
              context,
              settings,
              downloadUrl,
              displayUrl: displayDownloadUrl,
              suggestedFileName: suggestedDownloadFileName,
            ),
          );
        },
        playerController: _floatingVideoPlayerController,
      );
    } catch (error) {
      _onDebugLog('Failed to initialize floating video player: $error');
      _floatingVideoController?.dispose();
      _floatingVideoController = null;
      if (!context.mounted) {
        await closeFloatingVideoPlayer();
        return;
      }
      _showFloatingErrorOverlay(
        context: context,
        title: floatingTitle,
        message: '视频播放失败: $error',
        onDownload: () {
          unawaited(
            _downloadVideo(
              context,
              settings,
              downloadUrl,
              displayUrl: displayDownloadUrl,
              suggestedFileName: suggestedDownloadFileName,
            ),
          );
        },
      );
    }
  }

  VideoPlayerController _createVideoController(String playbackUrl) {
    final uri = Uri.parse(playbackUrl);
    final scheme = uri.scheme.toLowerCase();
    final options = VideoPlayerOptions(allowBackgroundPlayback: true);
    if (scheme == 'content') {
      return VideoPlayerController.contentUri(uri, videoPlayerOptions: options);
    }
    if (scheme == 'file') {
      return VideoPlayerController.file(
        File.fromUri(uri),
        videoPlayerOptions: options,
      );
    }
    return VideoPlayerController.networkUrl(uri, videoPlayerOptions: options);
  }

  void _showFloatingErrorOverlay({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onDownload,
  }) {
    _floatingVideoOverlay?.remove();
    _floatingVideoOverlay = FloatingVideoPlayer.show(
      context: context,
      title: title,
      errorMessage: message,
      onClose: () {
        unawaited(closeFloatingVideoPlayer());
      },
      onDownload: onDownload,
      playerController: _floatingVideoPlayerController,
    );
    _onShowSnackBar(message);
  }

  Future<void> _downloadVideo(
    BuildContext context,
    BrowserSettings settings,
    String url, {
    String? displayUrl,
    String? suggestedFileName,
  }) async {
    await _downloadCoordinator.startDownloadFromUrl(
      context: context,
      url: url,
      settings: settings,
      onStatus: _onShowSnackBar,
      dialogAnchorOverlay: _floatingVideoOverlay,
      displayUrl: displayUrl,
      suggestedFileName: suggestedFileName,
    );
  }

  Future<void> closeFloatingVideoPlayer() async {
    _videoDetectionTracker.rememberDismissedUrl(
      _videoDetectionTracker.activeUrl,
    );
    _floatingVideoOverlay?.remove();
    _floatingVideoOverlay = null;
    await _floatingVideoController?.dispose();
    _floatingVideoController = null;
    _videoDetectionTracker.activeUrl = null;
    _videoDetectionTracker.isProcessing = false;
    await _stopProxyServer();
  }

  Future<void> dispose() async {
    await closeFloatingVideoPlayer();
  }
}
