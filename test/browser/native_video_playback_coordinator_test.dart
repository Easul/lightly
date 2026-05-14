import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_video_playback_preparation_service.dart';
import 'package:lightly/browser/services/video_source_resolver.dart';
import 'package:lightly/pages/native_video_playback_coordinator.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('NativeVideoPlaybackCoordinator', () {
    test('initializes controller from prepared playback result', () async {
      final preparationService = BrowserVideoPlaybackPreparationService(
        loadSettings: () async => BrowserSettings.defaults(),
        resolveVideoSource: (_, __) async => const ResolvedVideoSource(
          videoId: 'abc',
          streamUrl: 'https://cdn.example.com/video.mp4',
          title: 'Title',
        ),
        ensureProxyServer: (_) async {},
        buildProxyPlaybackUrl: (url) => url,
        redactDownloadUrl: (url) => url,
      );

      final fakeController = _FakeVideoPlayerController();
      final coordinator = NativeVideoPlaybackCoordinator(
        playbackPreparationService: preparationService,
        createVideoController: (_) async => fakeController,
        initializeVideoController: (controller) async {
          (controller as _FakeVideoPlayerController).initialized = true;
        },
        createChewieController:
            ({
              required videoPlayerController,
              required compact,
              required aspectRatio,
            }) {
              return FakeChewieController(
                videoPlayerController: videoPlayerController,
              );
            },
      );

      final result = await coordinator.initializePlayer(
        requestedUrl: 'https://youtube.com/watch?v=abc',
        shouldResolveYoutube: true,
        compact: false,
      );

      expect(result.playbackUrl, 'https://cdn.example.com/video.mp4');
      expect(result.resolvedTitle, 'Title');
      expect(fakeController.initialized, isTrue);
    });
  });
}

class _FakeVideoPlayerController extends Fake implements VideoPlayerController {
  bool initialized = false;

  @override
  VideoPlayerValue get value => const VideoPlayerValue(
    duration: Duration.zero,
    isInitialized: true,
    size: Size(1600, 900),
  );

  @override
  Future<void> dispose() async {}
}

class FakeChewieController extends Fake implements ChewieController {
  FakeChewieController({required this.videoPlayerController});

  final VideoPlayerController videoPlayerController;
}
