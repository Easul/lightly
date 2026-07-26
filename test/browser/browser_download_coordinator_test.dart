import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/proxy/infrastructure/proxy_service.dart';
import 'package:lightly/browser/services/browser_download_coordinator.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';

void main() {
  group('BrowserDownloadCoordinator helpers', () {
    late BrowserDownloadCoordinator coordinator;

    setUp(() {
      coordinator = BrowserDownloadCoordinator(
        downloadService: BrowserDownloadService(
          now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
        downloadStore: BrowserDownloadStore(),
        proxyService: ProxyService(),
      );
    });

    test('normalizeFloatingDownloadTitle trims generic video title suffix', () {
      expect(
        BrowserDownloadCoordinator.normalizeFloatingDownloadTitle(
          'Example Clip - YouTube',
        ),
        'Example Clip',
      );
      expect(
        BrowserDownloadCoordinator.normalizeFloatingDownloadTitle('视频播放'),
        isNull,
      );
    });

    test(
      'resolveFloatingDownloadFileName prefers page title and mp4 suffix',
      () {
        expect(
          coordinator.resolveFloatingDownloadFileName(
            'https://example.com/video-stream',
            pageTitle: 'Demo Title',
          ),
          'Demo Title.mp4',
        );
      },
    );

    test(
      'resolveFloatingDownloadFileName forces mp4 for titled video downloads',
      () {
        expect(
          coordinator.resolveFloatingDownloadFileName(
            'https://example.com/video-stream',
            pageTitle: 'Clip.mkv',
          ),
          'Clip.mkv.mp4',
        );
      },
    );

    test('redactDownloadUrl removes embedded credentials only', () {
      expect(
        BrowserDownloadCoordinator.redactDownloadUrl(
          'https://user:pass@example.com/file.mp4?token=abc#frag',
        ),
        'https://example.com/file.mp4?token=abc#frag',
      );
    });
  });
}
