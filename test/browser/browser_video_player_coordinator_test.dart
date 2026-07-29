import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_service.dart';
import 'package:lightly/browser/services/browser_download_coordinator.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/features/video/application/browser_video_detection_tracker.dart';
import 'package:lightly/browser/services/browser_video_playback_preparation_service.dart';
import 'package:lightly/browser/services/browser_video_player_coordinator.dart';
import 'package:lightly/features/video/domain/video_source_resolver.dart';
import 'package:lightly/features/video/domain/floating_video_system_ui_runtime.dart';

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
          resolveVideoSource: (_, _) async => const ResolvedVideoSource(
            videoId: 'abc123',
            streamUrl: 'https://example.com/video.mp4',
            title: 'Video',
          ),
          ensureProxyServer: (_) async {},
          buildProxyPlaybackUrl: (url, _) => url,
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
        floatingVideoSystemUiRuntime: _FakeFloatingVideoSystemUiRuntime(),
      );
    });

    test('opens native player only for youtube urls when enabled', () {
      final enabledSettings = BrowserSettings.defaults().copyWith(
        nativeVideoPlayerEnabled: true,
      );
      final settingsWithLegacyParserEmpty = enabledSettings.copyWith(
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
          settingsWithLegacyParserEmpty,
        ),
        isTrue,
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

class _FakeFloatingVideoSystemUiRuntime
    implements FloatingVideoSystemUiRuntime {
  @override
  Future<void> setKeepScreenOn(bool keepOn) async {}
}
