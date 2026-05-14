import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/proxy_service.dart';
import 'package:lightly/browser/services/browser_download_coordinator.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/browser/services/browser_video_detection_tracker.dart';
import 'package:lightly/browser/services/browser_video_playback_preparation_service.dart';
import 'package:lightly/browser/services/browser_video_player_coordinator.dart';
import 'package:lightly/browser/services/video_source_resolver.dart';

void main() {
  group('BrowserVideoPlayerCoordinator', () {
    late BrowserVideoDetectionTracker tracker;
    late bool stoppedProxyServer;
    late BrowserVideoPlayerCoordinator coordinator;

    setUp(() {
      tracker = BrowserVideoDetectionTracker();
      stoppedProxyServer = false;
      coordinator = BrowserVideoPlayerCoordinator(
        playbackPreparationService: BrowserVideoPlaybackPreparationService(
          loadSettings: () async => BrowserSettings.defaults(),
          resolveVideoSource: (_, __) async => const ResolvedVideoSource(
            videoId: 'abc123',
            streamUrl: 'https://example.com/video.mp4',
            title: 'Video',
          ),
          ensureProxyServer: (_) async {},
          buildProxyPlaybackUrl: (url) => url,
          redactDownloadUrl: (url) => url,
        ),
        downloadCoordinator: BrowserDownloadCoordinator(
          downloadService: BrowserDownloadService(),
          downloadStore: BrowserDownloadStore(),
          proxyService: ProxyService(),
        ),
        videoDetectionTracker: tracker,
        stopProxyServer: () async {
          stoppedProxyServer = true;
        },
        onShowSnackBar: (_) {},
        onDebugLog: (_) {},
      );
    });

    test('opens native player only for youtube urls when enabled', () {
      final enabledSettings = BrowserSettings.defaults().copyWith(
        nativeVideoPlayerEnabled: true,
      );
      final parserDisabledSettings = enabledSettings.copyWith(
        nativeVideoParserApiBaseUrl: '',
      );
      final disabledSettings = BrowserSettings.defaults().copyWith(
        nativeVideoPlayerEnabled: false,
      );

      expect(
        coordinator.shouldOpenNativeVideoFromUrl(
          'https://www.youtube.com/watch?v=abc123',
          enabledSettings,
        ),
        isTrue,
      );
      expect(
        coordinator.shouldOpenNativeVideoFromUrl(
          'https://www.youtube.com/watch?v=abc123',
          disabledSettings,
        ),
        isFalse,
      );
      expect(
        coordinator.shouldOpenNativeVideoFromUrl(
          'https://www.youtube.com/watch?v=abc123',
          parserDisabledSettings,
        ),
        isFalse,
      );
      expect(
        coordinator.shouldOpenNativeVideoFromUrl(
          'https://example.com/video.mp4',
          enabledSettings,
        ),
        isFalse,
      );
    });

    test(
      'closeFloatingVideoPlayer resets tracker state and stops proxy',
      () async {
        tracker.activeUrl = 'https://example.com/video.mp4';
        tracker.isProcessing = true;

        await coordinator.closeFloatingVideoPlayer();

        expect(tracker.activeUrl, isNull);
        expect(tracker.isProcessing, isFalse);
        expect(stoppedProxyServer, isTrue);
      },
    );
  });
}
