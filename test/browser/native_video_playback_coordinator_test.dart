import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/application/video_playback_preparer.dart';
import 'package:lightly/pages/native_video_playback_coordinator.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('NativeVideoPlaybackCoordinator', () {
    test('initializes controller from prepared playback result', () async {
      final preparationService = _FakeVideoPlaybackPreparer(
        const PreparedVideoPlayback(
          playbackUrl: 'https://cdn.example.com/video.mp4',
          downloadUrl: 'https://cdn.example.com/video.mp4',
          displayDownloadUrl: 'https://youtube.com/watch?v=abc',
          resolvedTitle: 'Title',
        ),
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

class _FakeVideoPlaybackPreparer implements VideoPlaybackPreparer {
  const _FakeVideoPlaybackPreparer(this.result);

  final PreparedVideoPlayback result;

  @override
  Future<PreparedVideoPlayback> prepare({
    required String requestedUrl,
    required bool shouldResolveYoutube,
  }) async {
    return result;
  }
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

  @override
  final VideoPlayerController videoPlayerController;
}
