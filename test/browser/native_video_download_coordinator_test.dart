import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/browser/browser_settings.dart';
import 'package:lightly/browser/models/browser_download_record.dart';
import 'package:lightly/browser/proxy_service.dart';
import 'package:lightly/browser/services/browser_download_service.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/pages/native_video_download_coordinator.dart';

void main() {
  group('NativeVideoDownloadCoordinator', () {
    test('resolveNativeVideoDownloadFileName uses parser title', () {
      final service = BrowserDownloadService();

      expect(
        resolveNativeVideoDownloadFileName(
          downloadService: service,
          resolvedTitle: 'Example video title',
          resolvedPlaybackUrl: 'https://cdn.example.com/videoplayback?id=1',
          originalVideoUrl: 'https://youtube.com/watch?v=abc123',
        ),
        'Example video title.mp4',
      );
    });

    test('resolveNativeVideoDownloadFileName preserves title extension', () {
      final service = BrowserDownloadService();

      expect(
        resolveNativeVideoDownloadFileName(
          downloadService: service,
          resolvedTitle: 'Example/video:name.mp4',
          resolvedPlaybackUrl: 'https://cdn.example.com/videoplayback?id=1',
          originalVideoUrl: 'https://youtube.com/watch?v=abc123',
        ),
        'Example_video_name.mp4',
      );
    });

    test('resolveNativeVideoDownloadFileName falls back to playback url', () {
      final service = BrowserDownloadService();

      expect(
        resolveNativeVideoDownloadFileName(
          downloadService: service,
          resolvedTitle: ' ',
          resolvedPlaybackUrl: 'https://cdn.example.com/video.mp4?token=abc',
          originalVideoUrl: 'https://youtube.com/watch?v=abc123',
        ),
        'video.mp4',
      );
    });

    test('returns when user cancels confirmation', () async {
      final service = _FakeDownloadService();
      final store = _FakeDownloadStore();
      final coordinator = NativeVideoDownloadCoordinator(
        downloadService: service,
        downloadStore: store,
        proxyService: ProxyService(),
        loadSettings: () async => BrowserSettings.defaults(),
      );

      await coordinator.startDownload(
        playbackUrl: 'https://example.com/video.mp4',
        fileName: 'video.mp4',
        confirmDownload: (_) async => null,
        onStatus: (_) {},
      );

      expect(service.prepareCalled, isFalse);
      expect(store.inserted, isNull);
    });

    test('reports missing save path and skips insert', () async {
      final service = _FakeDownloadService(
        preparedRecord: BrowserDownloadRecord(
          url: 'https://example.com/video.mp4',
          fileName: 'video.mp4',
          status: 'pending',
          savedPath: '',
          totalBytes: 0,
          bytesReceived: 0,
          createdAt: DateTime(2024),
        ),
      );
      final store = _FakeDownloadStore();
      final messages = <String>[];
      final coordinator = NativeVideoDownloadCoordinator(
        downloadService: service,
        downloadStore: store,
        proxyService: ProxyService(),
        loadSettings: () async => BrowserSettings.defaults(),
      );

      await coordinator.startDownload(
        playbackUrl: 'https://example.com/video.mp4',
        fileName: 'video.mp4',
        confirmDownload: (_) async =>
            const DownloadConfirmationResult(fileName: 'video.mp4'),
        onStatus: messages.add,
      );

      expect(messages.single, '下载失败：无法确定保存路径');
      expect(store.inserted, isNull);
    });

    test('starts download after confirmation and prepared path', () async {
      final service = _FakeDownloadService(
        preparedRecord: BrowserDownloadRecord(
          url: 'https://example.com/video.mp4',
          fileName: 'video.mp4',
          status: 'pending',
          savedPath: '/tmp/video.mp4',
          totalBytes: 0,
          bytesReceived: 0,
          createdAt: DateTime(2024),
        ),
      );
      final store = _FakeDownloadStore();
      final messages = <String>[];
      final coordinator = NativeVideoDownloadCoordinator(
        downloadService: service,
        downloadStore: store,
        proxyService: ProxyService(),
        loadSettings: () async => BrowserSettings.defaults(),
      );

      await coordinator.startDownload(
        playbackUrl: 'https://example.com/video.mp4',
        fileName: 'video.mp4',
        confirmDownload: (_) async =>
            const DownloadConfirmationResult(fileName: 'renamed.mp4'),
        onStatus: messages.add,
      );

      expect(messages.first, '开始下载：renamed.mp4');
      expect(service.startCalled, isTrue);
      expect(store.inserted, isNotNull);
    });
  });
}

class _FakeDownloadService extends BrowserDownloadService {
  _FakeDownloadService({this.preparedRecord});

  final BrowserDownloadRecord? preparedRecord;
  bool prepareCalled = false;
  bool startCalled = false;

  @override
  Future<BrowserDownloadRecord> prepareDownload(
    String url,
    String filename, {
    int totalBytes = 0,
    bool useSystemDownloads = true,
  }) async {
    prepareCalled = true;
    return preparedRecord ??
        BrowserDownloadRecord(
          url: url,
          fileName: filename,
          status: 'pending',
          savedPath: '/tmp/$filename',
          totalBytes: totalBytes,
          bytesReceived: 0,
          createdAt: DateTime(2024),
        );
  }

  @override
  Future<void> startDownload({
    required String url,
    required BrowserDownloadRecord record,
    required String savedPath,
    required ProxyService proxyService,
    required BrowserSettings settings,
    required BrowserDownloadStore downloadStore,
    required void Function(String) onStatus,
  }) async {
    startCalled = true;
  }
}

class _FakeDownloadStore extends BrowserDownloadStore {
  BrowserDownloadRecord? inserted;

  @override
  Future<BrowserDownloadRecord> insert(BrowserDownloadRecord record) async {
    inserted = record;
    return record.copyWith(id: 1);
  }
}
