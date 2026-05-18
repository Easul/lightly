import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/services/browser_video_playback_preparation_service.dart';
import 'package:lightly/browser/services/video_source_resolver.dart';

void main() {
  group('BrowserVideoPlaybackPreparationService', () {
    test('returns passthrough values for non-youtube playback', () async {
      final service = BrowserVideoPlaybackPreparationService(
        loadSettings: () async => BrowserSettings.defaults(),
        resolveVideoSource: (_, __) async {
          throw StateError('should not resolve');
        },
        ensureProxyServer: (_) async {},
        buildProxyPlaybackUrl: (url) => 'proxy:$url',
        redactDownloadUrl: (url) => 'redacted:$url',
      );

      final prepared = await service.prepare(
        requestedUrl: 'https://example.com/video.mp4',
        shouldResolveYoutube: false,
      );

      expect(prepared.playbackUrl, 'https://example.com/video.mp4');
      expect(prepared.downloadUrl, 'https://example.com/video.mp4');
      expect(
        prepared.displayDownloadUrl,
        'redacted:https://example.com/video.mp4',
      );
      expect(prepared.resolvedTitle, isNull);
    });

    test('uses resolved stream directly when proxy is disabled', () async {
      final service = BrowserVideoPlaybackPreparationService(
        loadSettings: () async =>
            BrowserSettings.defaults().copyWith(proxyEnabled: false),
        resolveVideoSource: (_, __) async => const ResolvedVideoSource(
          videoId: 'abc123',
          title: 'Resolved title',
          streamUrl: 'https://cdn.example.com/stream.m3u8',
        ),
        ensureProxyServer: (_) async {
          throw StateError('should not start proxy');
        },
        buildProxyPlaybackUrl: (url) => 'proxy:$url',
        redactDownloadUrl: (url) => 'redacted:$url',
      );

      final prepared = await service.prepare(
        requestedUrl: 'https://youtube.com/watch?v=abc123',
        shouldResolveYoutube: true,
      );

      expect(prepared.playbackUrl, 'https://cdn.example.com/stream.m3u8');
      expect(prepared.downloadUrl, 'https://cdn.example.com/stream.m3u8');
      expect(
        prepared.displayDownloadUrl,
        'redacted:https://youtube.com/watch?v=abc123',
      );
      expect(prepared.resolvedTitle, 'Resolved title');
    });

    test('uses local proxy playback url when proxy is enabled', () async {
      var proxyStarted = false;
      final service = BrowserVideoPlaybackPreparationService(
        loadSettings: () async => BrowserSettings.defaults().copyWith(
          proxyEnabled: true,
          proxyHost: '127.0.0.1',
          proxyPort: 1080,
        ),
        resolveVideoSource: (_, __) async => const ResolvedVideoSource(
          videoId: 'abc123',
          title: 'Resolved title',
          streamUrl: 'https://cdn.example.com/stream.m3u8',
        ),
        ensureProxyServer: (_) async {
          proxyStarted = true;
        },
        buildProxyPlaybackUrl: (url) =>
            'http://127.0.0.1:12345/proxy?url=${Uri.encodeComponent(url)}',
        redactDownloadUrl: (url) => url,
      );

      final prepared = await service.prepare(
        requestedUrl: 'https://youtube.com/watch?v=abc123',
        shouldResolveYoutube: true,
      );

      expect(proxyStarted, isTrue);
      expect(
        prepared.playbackUrl,
        'http://127.0.0.1:12345/proxy?url=https%3A%2F%2Fcdn.example.com%2Fstream.m3u8',
      );
      expect(prepared.downloadUrl, 'https://cdn.example.com/stream.m3u8');
      expect(prepared.resolvedTitle, 'Resolved title');
    });

    test('fails youtube resolution when parser api setting is empty', () async {
      var resolveCalls = 0;
      final service = BrowserVideoPlaybackPreparationService(
        loadSettings: () async => BrowserSettings.defaults().copyWith(
          nativeVideoPlayerEnabled: true,
          nativeVideoParserApiBaseUrl: '',
        ),
        resolveVideoSource: (_, __) async {
          resolveCalls++;
          throw StateError('should not resolve');
        },
        ensureProxyServer: (_) async {
          throw StateError('should not start proxy');
        },
        buildProxyPlaybackUrl: (url) => 'proxy:$url',
        redactDownloadUrl: (url) => 'redacted:$url',
      );

      await expectLater(
        service.prepare(
          requestedUrl: 'https://youtube.com/watch?v=abc123',
          shouldResolveYoutube: true,
        ),
        throwsA(
          isA<VideoResolutionException>().having(
            (error) => error.message,
            'message',
            '请先在设置中配置 YouTube 解析接口',
          ),
        ),
      );

      expect(resolveCalls, 0);
    });
  });
}
