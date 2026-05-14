import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import '../browser/browser_settings_service.dart';
import '../browser/models/browser_download_record.dart';
import '../browser/proxy_service.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';
import '../browser/services/browser_shared_services.dart';
import '../browser/services/browser_video_playback_preparation_service.dart';
import '../browser/services/external_api_video_source_resolver.dart';
import '../browser/services/video_proxy_server.dart';
import '../browser/services/video_source_resolver.dart';
import '../browser/utils/youtube_long_press_utils.dart';
import '../widgets/native_video/native_video_overlay.dart';
import 'native_video_download_coordinator.dart';
import 'native_video_gesture_controller.dart';
import 'native_video_playback_coordinator.dart';

class NativeVideoPlayerPage extends StatelessWidget {
  const NativeVideoPlayerPage({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('视频播放'),
      ),
      body: NativeVideoPlayerView(videoUrl: videoUrl),
    );
  }
}

class NativeVideoPlayerDialog extends StatelessWidget {
  const NativeVideoPlayerDialog({super.key, required this.videoUrl});

  final String videoUrl;

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '视频播放',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NativeVideoPlayerView(videoUrl: videoUrl, compact: true),
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
  });

  final String videoUrl;
  final bool compact;

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
              proxyService: _proxyService,
              settings: settings,
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
        return VideoPlayerController.networkUrl(Uri.parse(playbackUrl));
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

  bool get _isYouTubeUrl =>
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
    } catch (e, stackTrace) {
      if (!mounted) return;
      _logDebug('NativeVideoPlayer: initialization failed: $e');
      _logDebug('NativeVideoPlayer: stack trace: $stackTrace');
      setState(() {
        _isInitializing = false;
        _errorMessage = _isYouTubeUrl
            ? 'YouTube 视频解析失败\n${e.toString()}'
            : '播放失败: ${e.toString()}';
      });
    }
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

  String _resolveDownloadFileName() {
    final title = _resolvedTitle?.trim();
    if (title != null && title.isNotEmpty) {
      final hasExtension = RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(title);
      return _downloadService.sanitizeFileName(
        hasExtension ? title : '$title.mp4',
      );
    }
    return _downloadService.resolveFileNameFromUrl(
      _resolvedPlaybackUrl ?? widget.videoUrl,
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _gestureHintNotifier.dispose();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    unawaited(_videoProxyServer.stop());
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
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
        onDownload: _downloadCurrentVideo,
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
