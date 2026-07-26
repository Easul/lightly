import '../../features/proxy/infrastructure/proxy_service.dart';
import '../../features/video/application/native_video_download_runtime.dart';
import '../browser_settings.dart';
import 'browser_download_service.dart';
import 'browser_download_store.dart';

class BrowserNativeVideoDownloadRuntime implements NativeVideoDownloadRuntime {
  const BrowserNativeVideoDownloadRuntime({
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

  @override
  String sanitizeFileName(String name) =>
      _downloadService.sanitizeFileName(name);

  @override
  String resolveFileNameFromUrl(String url) =>
      _downloadService.resolveFileNameFromUrl(url);

  @override
  Future<NativeVideoDownloadStartResult> startDownload({
    required String url,
    required String fileName,
    required void Function() onStarted,
    required void Function(String message) onStatus,
  }) async {
    final preparedRecord = await _downloadService.prepareDownload(
      url,
      fileName,
    );
    final savedPath = preparedRecord.savedPath;
    if (savedPath == null || savedPath.isEmpty) {
      return NativeVideoDownloadStartResult.missingSavePath;
    }

    final record = await _downloadStore.insert(preparedRecord);
    final settings = await _loadSettings();
    onStarted();
    await _downloadService.startDownload(
      url: url,
      record: record,
      savedPath: savedPath,
      proxyService: _proxyService,
      settings: settings,
      downloadStore: _downloadStore,
      onStatus: onStatus,
    );
    return NativeVideoDownloadStartResult.started;
  }
}
