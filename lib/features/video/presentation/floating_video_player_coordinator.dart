import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../application/browser_video_detection_tracker.dart';
import '../application/video_playback_preparer.dart';
import '../domain/floating_video_system_ui_runtime.dart';
import '../domain/youtube_long_press_utils.dart';
import 'floating_video_download_runtime.dart';
import 'widgets/floating_video_player.dart';

class FloatingVideoPlayerCoordinator<TDownloadContext> {
  FloatingVideoPlayerCoordinator({
    required VideoPlaybackPreparer playbackPreparationService,
    required FloatingVideoDownloadRuntime<TDownloadContext> downloadRuntime,
    required BrowserVideoDetectionTracker videoDetectionTracker,
    required Future<void> Function() stopProxyServer,
    required void Function(String) onShowSnackBar,
    required void Function(String) onDebugLog,
    required FloatingVideoSystemUiRuntime floatingVideoSystemUiRuntime,
  }) : _playbackPreparationService = playbackPreparationService,
       _downloadRuntime = downloadRuntime,
       _videoDetectionTracker = videoDetectionTracker,
       _stopProxyServer = stopProxyServer,
       _onShowSnackBar = onShowSnackBar,
       _onDebugLog = onDebugLog,
       _floatingVideoSystemUiRuntime = floatingVideoSystemUiRuntime;

  final VideoPlaybackPreparer _playbackPreparationService;
  final FloatingVideoDownloadRuntime<TDownloadContext> _downloadRuntime;
  final BrowserVideoDetectionTracker _videoDetectionTracker;
  final Future<void> Function() _stopProxyServer;
  final void Function(String) _onShowSnackBar;
  final void Function(String) _onDebugLog;
  final FloatingVideoSystemUiRuntime _floatingVideoSystemUiRuntime;

  OverlayEntry? _floatingVideoOverlay;
  VideoPlayerController? _floatingVideoController;
  final FloatingVideoPlayerController _floatingVideoPlayerController =
      FloatingVideoPlayerController();
  int _showGeneration = 0;

  static FloatingVideoPlayerCoordinator<dynamic>? _activeFloatingCoordinator;
  static bool _globalLooping = false;

  OverlayEntry? get floatingVideoOverlay => _floatingVideoOverlay;
  FloatingVideoPlayerController get floatingVideoPlayerController =>
      _floatingVideoPlayerController;
  bool get hasActiveOverlay => _floatingVideoOverlay != null;
  bool get isLooping => _globalLooping;

  bool supportsResolvedPlayback(String url) =>
      deriveYouTubeLongPressTargets(url) != null;

  String? _normalizeFloatingTitle(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalized = _downloadRuntime.normalizeTitle(trimmed);
    return normalized?.trim().isNotEmpty == true ? normalized : null;
  }

  Future<void> showFloatingVideoPlayer({
    required BuildContext context,
    required String url,
    required bool shouldResolveYoutube,
    required TDownloadContext downloadContext,
    required String currentPageTitle,
  }) async {
    await _replaceActiveFloatingCoordinator();
    await closeFloatingVideoPlayer();
    if (!context.mounted) {
      return;
    }
    final showGeneration = ++_showGeneration;
    _activeFloatingCoordinator = this;
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
      isLooping: _globalLooping,
      onLoopingChanged: _setLooping,
      playerController: _floatingVideoPlayerController,
      systemUiRuntime: _floatingVideoSystemUiRuntime,
    );

    var playbackUrl = url;
    var downloadUrl = url;
    var displayDownloadUrl = _downloadRuntime.redactUrl(url);
    String? suggestedDownloadFileName;

    try {
      final preparedPlayback = await _playbackPreparationService.prepare(
        requestedUrl: url,
        shouldResolveYoutube: shouldResolveYoutube,
      );
      if (!_isCurrentShow(showGeneration)) {
        return;
      }
      playbackUrl = preparedPlayback.playbackUrl;
      downloadUrl = preparedPlayback.downloadUrl;
      displayDownloadUrl = preparedPlayback.displayDownloadUrl;

      if (shouldResolveYoutube) {
        floatingTitle =
            _normalizeFloatingTitle(preparedPlayback.resolvedTitle) ??
            pageTitle ??
            '视频播放';
        suggestedDownloadFileName = _downloadRuntime.resolveFileName(
          downloadUrl,
          pageTitle: floatingTitle,
        );
      }
    } catch (error) {
      if (shouldResolveYoutube) {
        _onDebugLog('Failed to resolve YouTube video: $error');
        if (!_isCurrentShow(showGeneration)) {
          return;
        }
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
                      downloadContext,
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
      await controller.setLooping(_globalLooping);
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!_isCurrentShow(showGeneration)) {
        await controller.dispose();
        if (_floatingVideoController == controller) {
          _floatingVideoController = null;
        }
        return;
      }
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
        isLooping: _globalLooping,
        onLoopingChanged: _setLooping,
        onDownload: () {
          unawaited(
            _downloadVideo(
              context,
              downloadContext,
              downloadUrl,
              displayUrl: displayDownloadUrl,
              suggestedFileName: suggestedDownloadFileName,
            ),
          );
        },
        playerController: _floatingVideoPlayerController,
        systemUiRuntime: _floatingVideoSystemUiRuntime,
      );
    } catch (error) {
      _onDebugLog('Failed to initialize floating video player: $error');
      _floatingVideoController?.dispose();
      _floatingVideoController = null;
      if (!_isCurrentShow(showGeneration)) {
        return;
      }
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
              downloadContext,
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

  bool _isCurrentShow(int generation) {
    return _showGeneration == generation &&
        _activeFloatingCoordinator == this &&
        _floatingVideoOverlay != null;
  }

  Future<void> _replaceActiveFloatingCoordinator() async {
    final activeCoordinator = _activeFloatingCoordinator;
    if (activeCoordinator == null || activeCoordinator == this) {
      return;
    }
    await activeCoordinator.closeFloatingVideoPlayer();
  }

  void _setLooping(bool value) {
    _globalLooping = value;
    unawaited(_floatingVideoController?.setLooping(value));
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
      isLooping: _globalLooping,
      onLoopingChanged: _setLooping,
      onDownload: onDownload,
      playerController: _floatingVideoPlayerController,
      systemUiRuntime: _floatingVideoSystemUiRuntime,
    );
    _onShowSnackBar(message);
  }

  Future<void> _downloadVideo(
    BuildContext context,
    TDownloadContext downloadContext,
    String url, {
    String? displayUrl,
    String? suggestedFileName,
  }) async {
    await _downloadRuntime.startDownload(
      context: context,
      downloadContext: downloadContext,
      url: url,
      onStatus: _onShowSnackBar,
      dialogAnchorOverlay: _floatingVideoOverlay,
      displayUrl: displayUrl,
      suggestedFileName: suggestedFileName,
    );
  }

  Future<void> closeFloatingVideoPlayer() async {
    _showGeneration++;
    _videoDetectionTracker.rememberDismissedUrl(
      _videoDetectionTracker.activeUrl,
    );
    _floatingVideoOverlay?.remove();
    _floatingVideoOverlay = null;
    await _floatingVideoController?.dispose();
    _floatingVideoController = null;
    _videoDetectionTracker.activeUrl = null;
    _videoDetectionTracker.isProcessing = false;
    if (_activeFloatingCoordinator == this) {
      _activeFloatingCoordinator = null;
    }
    await _stopProxyServer();
  }

  Future<void> dispose() async {
    await closeFloatingVideoPlayer();
  }
}
