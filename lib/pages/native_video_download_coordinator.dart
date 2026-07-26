import '../browser/browser_settings.dart';
import '../browser/models/browser_download_record.dart';
import '../features/proxy/infrastructure/proxy_service.dart';
import '../browser/services/browser_download_service.dart';
import '../browser/services/browser_download_store.dart';

String resolveNativeVideoDownloadFileName({
  required BrowserDownloadService downloadService,
  required String? resolvedTitle,
  required String? resolvedPlaybackUrl,
  required String originalVideoUrl,
}) {
  final title = resolvedTitle?.trim();
  if (title != null && title.isNotEmpty) {
    final hasExtension = RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(title);
    return downloadService.sanitizeFileName(
      hasExtension ? title : '$title.mp4',
    );
  }
  return downloadService.resolveFileNameFromUrl(
    resolvedPlaybackUrl ?? originalVideoUrl,
  );
}

typedef NativeVideoDownloadConfirmation =
    Future<DownloadConfirmationResult?> Function(BrowserDownloadRecord record);

class NativeVideoDownloadCoordinator {
  const NativeVideoDownloadCoordinator({
    required BrowserDownloadService downloadService,
    required BrowserDownloadStore downloadStore,
    required ProxyService proxyService,
    required Future<BrowserSettings> Function() loadSettings,
  }) : _downloadService = downloadService,
       _downloadStore = downloadStore,
       _proxyService = proxyService,
       _loadSettings = loadSettings;

  final BrowserDownloadService _downloadService;
  final BrowserDownloadStore _downloadStore;
  final ProxyService _proxyService;
  final Future<BrowserSettings> Function() _loadSettings;

  Future<void> startDownload({
    required String playbackUrl,
    required String fileName,
    required NativeVideoDownloadConfirmation confirmDownload,
    required void Function(String message) onStatus,
  }) async {
    final pendingRecord = BrowserDownloadRecord(
      url: playbackUrl,
      fileName: fileName,
      status: 'pending',
      savedPath: null,
      totalBytes: 0,
      bytesReceived: 0,
      createdAt: DateTime.now(),
    );

    final confirmation = await confirmDownload(pendingRecord);
    if (confirmation == null) {
      return;
    }

    final preparedRecord = await _downloadService.prepareDownload(
      playbackUrl,
      confirmation.fileName,
    );
    final savedPath = preparedRecord.savedPath;
    if (savedPath == null || savedPath.isEmpty) {
      onStatus('下载失败：无法确定保存路径');
      return;
    }

    final record = await _downloadStore.insert(preparedRecord);
    final settings = await _loadSettings();
    onStatus('开始下载：${confirmation.fileName}');
    await _downloadService.startDownload(
      url: playbackUrl,
      record: record,
      savedPath: savedPath,
      proxyService: _proxyService,
      settings: settings,
      downloadStore: _downloadStore,
      onStatus: onStatus,
    );
  }
}
