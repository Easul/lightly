import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import '../browser/browser_settings_service.dart';
import '../features/proxy/infrastructure/proxy_service.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';
import '../browser/services/browser_shared_services.dart';
import '../browser/services/browser_video_playback_preparation_service.dart';
import '../browser/services/external_api_video_source_resolver.dart';
import '../browser/services/video_proxy_server.dart';
import '../features/video/domain/video_source_resolver.dart';
import '../services/app_log_service.dart';
import '../features/video/domain/youtube_long_press_utils.dart';
import '../services/app_toast.dart';
import '../features/video/application/native_video_gesture_controller.dart';
import '../features/video/presentation/widgets/native_video_overlay.dart';
import '../features/video/presentation/widgets/native_video_player_widgets.dart';
import '../features/video/presentation/native_video_playback_coordinator.dart';
import 'native_video_download_coordinator.dart';

class NativeVideoPlayerPage extends StatelessWidget {
  const NativeVideoPlayerPage({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: NativeVideoPlayerView(videoUrl: videoUrl)),
    );
  }
}

class NativeVideoPlayerDialog extends StatefulWidget {
  const NativeVideoPlayerDialog({
    super.key,
    required this.videoUrl,
    this.resolveYouTube = true,
    this.showDownloadAction = true,
  });

  final String videoUrl;
  final bool resolveYouTube;
  final bool showDownloadAction;

  @override
  State<NativeVideoPlayerDialog> createState() =>
      _NativeVideoPlayerDialogState();
}

class _NativeVideoPlayerDialogState extends State<NativeVideoPlayerDialog> {
  String? _resolvedTitle;
  bool _loopingEnabled = false;

  void _handleResolvedTitle(String? title) {
    final normalizedTitle = title?.trim();
    final nextTitle = normalizedTitle?.isNotEmpty == true
        ? normalizedTitle
        : null;
    if (_resolvedTitle == nextTitle || !mounted) {
      return;
    }
    setState(() {
      _resolvedTitle = nextTitle;
    });
  }

  void _toggleLooping() {
    if (!mounted) {
      return;
    }
    setState(() {
      _loopingEnabled = !_loopingEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            NativeVideoDialogHeader(
              title: _resolvedTitle,
              loopingEnabled: _loopingEnabled,
              onToggleLooping: _toggleLooping,
            ),
            Expanded(
              child: NativeVideoPlayerView(
                videoUrl: widget.videoUrl,
                compact: true,
                loopingEnabled: _loopingEnabled,
                resolveYouTube: widget.resolveYouTube,
                showDownloadAction: widget.showDownloadAction,
                onResolvedTitle: _handleResolvedTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NativeVideoPlayerView extends StatefulWidget {
  const NativeVideoPlayerView({
    super.key,
    required this.videoUrl,
    this.compact = false,
    this.loopingEnabled = false,
    this.resolveYouTube = true,
    this.showDownloadAction = true,
    this.onResolvedTitle,
  });

  final String videoUrl;
  final bool compact;
  final bool loopingEnabled;
  final bool resolveYouTube;
  final bool showDownloadAction;
  final ValueChanged<String?>? onResolvedTitle;

  @override
  State<NativeVideoPlayerView> createState() => _NativeVideoPlayerViewState();
}

class _NativeVideoPlayerViewState extends State<NativeVideoPlayerView> {
  static const double _gestureSensitivity = 320;

  final BrowserSharedServices _sharedServices = BrowserSharedServices.instance;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  VideoSourceResolver? _videoResolver;
  BrowserDownloadService get _downloadService =>
      _sharedServices.downloadService;
  BrowserDownloadStore get _downloadStore => _sharedServices.downloadStore;
  BrowserSettingsService get _settingsService =>
      _sharedServices.settingsService;
  ProxyService get _proxyService => _sharedServices.proxyService;
  final VideoProxyServer _videoProxyServer = VideoProxyServer();
  late final BrowserVideoPlaybackPreparationService
  _videoPlaybackPreparationService;
  late final NativeVideoDownloadCoordinator _downloadCoordinator;
  late final NativeVideoPlaybackCoordinator _playbackCoordinator;
  final ValueNotifier<String?> _gestureHintNotifier = ValueNotifier<String?>(
    null,
  );
  final NativeVideoGestureController _gestureController =
      NativeVideoGestureController();

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  bool _isInitializing = true;
  String? _errorMessage;
  String? _resolvedTitle;
  String? _resolvedPlaybackUrl;
  double _brightness = 0.5;
  double _volume = 0.5;
  double _previousPlayerVolume = 1.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _videoPlaybackPreparationService = BrowserVideoPlaybackPreparationService(
      loadSettings: _settingsService.loadSettings,
      resolveVideoSource: (url, settings) {
        final resolver =
            _videoResolver ??
            ExternalApiVideoSourceResolver(
              apiBaseUrl: settings.normalizedNativeVideoParserApiBaseUrl,
              proxyResolver: settings.shouldApplyProxy
                  ? (uri) => _proxyService.findProxyForDownload(
                      settings.proxyConfiguration,
                      uri,
                    )
                  : null,
            );
        return resolver.resolve(url);
      },
      ensureProxyServer: (settings) {
        return _videoProxyServer.start(
          proxyService: _proxyService,
          settings: settings,
        );
      },
      buildProxyPlaybackUrl: _videoProxyServer.buildProxyUrl,
      redactDownloadUrl: (url) => url,
      onDebugLog: _logDebug,
    );
    _playbackCoordinator = NativeVideoPlaybackCoordinator(
      playbackPreparationService: _videoPlaybackPreparationService,
      createVideoController: (playbackUrl) async {
        final uri = Uri.parse(playbackUrl);
        final scheme = uri.scheme.toLowerCase();
        if (scheme == 'content') {
          return VideoPlayerController.contentUri(
            uri,
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          );
        }
        if (scheme == 'file') {
          return VideoPlayerController.file(
            File.fromUri(uri),
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          );
        }
        return VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        );
      },
      initializeVideoController: (controller) async {
        await controller.initialize();
      },
      createChewieController: buildNativeVideoChewieController,
      onDebugLog: _logDebug,
    );
    _downloadCoordinator = NativeVideoDownloadCoordinator(
      downloadService: _downloadService,
      downloadStore: _downloadStore,
      proxyService: _proxyService,
      loadSettings: _settingsService.loadSettings,
    );
    _initializePlayer();
    _initializeSystemValues();
  }

  @override
  void didUpdateWidget(covariant NativeVideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loopingEnabled != widget.loopingEnabled) {
      unawaited(_applyLoopingPreference());
    }
  }

  bool get _isYouTubeUrl =>
      widget.resolveYouTube &&
      deriveYouTubeLongPressTargets(widget.videoUrl) != null &&
      (widget.videoUrl.contains('youtube.com') ||
          widget.videoUrl.contains('youtu.be'));

  Future<void> _initializeSystemValues() async {
    try {
      final brightness = await ScreenBrightness().current;
      final volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      setState(() {
        _brightness = brightness;
        _volume = volume;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _initializePlayer() async {
    try {
      final result = await _playbackCoordinator.initializePlayer(
        requestedUrl: widget.videoUrl,
        shouldResolveYoutube: _isYouTubeUrl,
        compact: widget.compact,
      );

      if (!mounted) {
        await result.videoPlayerController.dispose();
        result.chewieController.dispose();
        return;
      }

      setState(() {
        _resolvedTitle = result.resolvedTitle;
        _resolvedPlaybackUrl = result.playbackUrl;
        _videoPlayerController = result.videoPlayerController;
        _chewieController = result.chewieController;
        _isInitializing = false;
      });
      await _applyLoopingPreference();
      widget.onResolvedTitle?.call(result.resolvedTitle);
    } catch (e, stackTrace) {
      if (!mounted) return;
      _logDebug('NativeVideoPlayer: initialization failed: $e');
      _logDebug('NativeVideoPlayer: stack trace: $stackTrace');
      recordRuntimeLog(
        'NativeVideoPlayer',
        'Player initialization failed',
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'errorType': e.runtimeType.toString(),
          'isYouTube': _isYouTubeUrl,
          'resolveYouTube': widget.resolveYouTube,
        },
      );
      setState(() {
        _isInitializing = false;
        _errorMessage = _isYouTubeUrl
            ? 'YouTube 视频播放失败\n${e.toString()}'
            : '播放失败: ${e.toString()}';
      });
    }
  }

  Future<void> _applyLoopingPreference() async {
    final controller = _videoPlayerController;
    if (controller == null) {
      return;
    }
    try {
      await controller.setLooping(widget.loopingEnabled);
    } catch (_) {}
  }

  void _startGesture(DragStartDetails details, double maxWidth) {
    _gestureController.startGesture(
      localDx: details.localPosition.dx,
      maxWidth: maxWidth,
      brightness: _brightness,
      volume: _volume,
    );
  }

  void _updateGesture(DragUpdateDetails details) {
    final action = _gestureController.updateGesture(
      primaryDelta: details.primaryDelta ?? 0,
      sensitivity: _gestureSensitivity,
    );
    if (action == null) {
      return;
    }

    if (action.side == NativeVideoGestureControlSide.brightness) {
      _applyBrightness(action.nextValue, action.hint);
    } else {
      _applyVolume(action.nextValue, action.hint);
    }
  }

  void _endGesture() {
    _gestureController.endGesture();
    _gestureHintNotifier.value = null;
  }

  void _applyBrightness(double value, String hint) {
    if ((_brightness - value).abs() < 0.01) {
      return;
    }
    _brightness = value;
    _gestureHintNotifier.value = hint;
    unawaited(ScreenBrightness().setScreenBrightness(value));
  }

  void _applyVolume(double value, String hint) {
    if ((_volume - value).abs() < 0.01) {
      return;
    }
    _volume = value;
    _gestureHintNotifier.value = hint;
    unawaited(VolumeController.instance.setVolume(value));
  }

  void _toggleMute() {
    final controller = _videoPlayerController;
    if (controller == null) {
      return;
    }
    setState(() {
      if (_isMuted) {
        _isMuted = false;
        unawaited(controller.setVolume(_previousPlayerVolume));
      } else {
        _previousPlayerVolume = _previousPlayerVolume <= 0
            ? 1.0
            : _previousPlayerVolume;
        _isMuted = true;
        unawaited(controller.setVolume(0));
      }
    });
  }

  String _resolveDownloadFileName() {
    return resolveNativeVideoDownloadFileName(
      downloadService: _downloadService,
      resolvedTitle: _resolvedTitle,
      resolvedPlaybackUrl: _resolvedPlaybackUrl,
      originalVideoUrl: widget.videoUrl,
    );
  }

  Future<void> _downloadCurrentVideo() async {
    final playbackUrl = _resolvedPlaybackUrl;
    if (playbackUrl == null || playbackUrl.isEmpty) {
      return;
    }

    await _downloadCoordinator.startDownload(
      playbackUrl: playbackUrl,
      fileName: _resolveDownloadFileName(),
      confirmDownload: (pendingRecord) {
        return _downloadService.showConfirmDialog(context, pendingRecord);
      },
      onStatus: _showSnackBar,
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    unawaited(AppToast.show(message));
  }

  @override
  void dispose() {
    _gestureHintNotifier.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    unawaited(_videoProxyServer.stop());
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const NativeVideoLoadingView();
    }

    if (_errorMessage != null) {
      return NativeVideoErrorView(
        message: _errorMessage!,
        onClose: Navigator.of(context).maybePop,
      );
    }

    final chewieController = _chewieController;
    if (chewieController == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) => NativeVideoOverlay(
        chewieController: chewieController,
        compact: widget.compact,
        resolvedTitle: _resolvedTitle,
        onDownload: widget.showDownloadAction ? _downloadCurrentVideo : null,
        isMuted: _isMuted,
        onMuteToggle: _toggleMute,
        onClose: widget.compact ? null : Navigator.of(context).maybePop,
        gestureHintNotifier: _gestureHintNotifier,
        onVerticalDragStart: (details) =>
            _startGesture(details, constraints.maxWidth),
        onVerticalDragUpdate: _updateGesture,
        onVerticalDragEnd: (_) => _endGesture(),
        onVerticalDragCancel: _endGesture,
      ),
    );
  }
}
