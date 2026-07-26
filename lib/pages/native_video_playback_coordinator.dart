import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../browser/services/browser_video_playback_preparation_service.dart';
import '../features/video/domain/video_source_resolver.dart';

class NativeVideoPlaybackResult {
  const NativeVideoPlaybackResult({
    required this.playbackUrl,
    required this.resolvedTitle,
    required this.videoPlayerController,
    required this.chewieController,
  });

  final String playbackUrl;
  final String? resolvedTitle;
  final VideoPlayerController videoPlayerController;
  final ChewieController chewieController;
}

class NativeVideoPlaybackCoordinator {
  const NativeVideoPlaybackCoordinator({
    required BrowserVideoPlaybackPreparationService playbackPreparationService,
    required Future<VideoPlayerController> Function(String playbackUrl)
    createVideoController,
    required Future<void> Function(VideoPlayerController controller)
    initializeVideoController,
    required ChewieController Function({
      required VideoPlayerController videoPlayerController,
      required bool compact,
      required double aspectRatio,
    })
    createChewieController,
    void Function(String message)? onDebugLog,
  }) : _playbackPreparationService = playbackPreparationService,
       _createVideoController = createVideoController,
       _initializeVideoController = initializeVideoController,
       _createChewieController = createChewieController,
       _onDebugLog = onDebugLog;

  final BrowserVideoPlaybackPreparationService _playbackPreparationService;
  final Future<VideoPlayerController> Function(String playbackUrl)
  _createVideoController;
  final Future<void> Function(VideoPlayerController controller)
  _initializeVideoController;
  final ChewieController Function({
    required VideoPlayerController videoPlayerController,
    required bool compact,
    required double aspectRatio,
  })
  _createChewieController;
  final void Function(String message)? _onDebugLog;

  Future<NativeVideoPlaybackResult> initializePlayer({
    required String requestedUrl,
    required bool shouldResolveYoutube,
    required bool compact,
  }) async {
    final preparedPlayback = await _playbackPreparationService.prepare(
      requestedUrl: requestedUrl,
      shouldResolveYoutube: shouldResolveYoutube,
    );
    final playbackUrl = preparedPlayback.playbackUrl;

    final controller = await _createVideoController(playbackUrl);
    _onDebugLog?.call(
      'NativeVideoPlayer: initializing controller for $playbackUrl',
    );

    try {
      await _initializeVideoController(
        controller,
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException catch (_) {
      await controller.dispose();
      throw const VideoResolutionException('视频加载超时（20秒），请检查网络连接或代理设置');
    }

    final ratio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    final chewieController = _createChewieController(
      videoPlayerController: controller,
      compact: compact,
      aspectRatio: ratio,
    );

    return NativeVideoPlaybackResult(
      playbackUrl: playbackUrl,
      resolvedTitle: preparedPlayback.resolvedTitle,
      videoPlayerController: controller,
      chewieController: chewieController,
    );
  }
}

ChewieController buildNativeVideoChewieController({
  required VideoPlayerController videoPlayerController,
  required bool compact,
  required double aspectRatio,
}) {
  return ChewieController(
    videoPlayerController: videoPlayerController,
    autoPlay: true,
    looping: false,
    allowFullScreen: !compact,
    allowMuting: true,
    allowPlaybackSpeedChanging: true,
    showControlsOnInitialize: true,
    aspectRatio: aspectRatio,
    errorBuilder: (context, errorMessage) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '视频播放失败\n$errorMessage',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    },
    deviceOrientationsOnEnterFullScreen: const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    deviceOrientationsAfterFullScreen: const <DeviceOrientation>[],
  );
}
