import '../browser_settings.dart';
import 'video_source_resolver.dart';

class PreparedVideoPlayback {
  const PreparedVideoPlayback({
    required this.playbackUrl,
    required this.downloadUrl,
    required this.displayDownloadUrl,
    this.resolvedTitle,
  });

  final String playbackUrl;
  final String downloadUrl;
  final String displayDownloadUrl;
  final String? resolvedTitle;
}

class BrowserVideoPlaybackPreparationService {
  BrowserVideoPlaybackPreparationService({
    required Future<BrowserSettings> Function() loadSettings,
    required Future<ResolvedVideoSource> Function(String, BrowserSettings)
    resolveVideoSource,
    required Future<void> Function(BrowserSettings) ensureProxyServer,
    required String Function(String) buildProxyPlaybackUrl,
    required String Function(String) redactDownloadUrl,
    void Function(String message)? onDebugLog,
  }) : _loadSettings = loadSettings,
       _resolveVideoSource = resolveVideoSource,
       _ensureProxyServer = ensureProxyServer,
       _buildProxyPlaybackUrl = buildProxyPlaybackUrl,
       _redactDownloadUrl = redactDownloadUrl,
       _onDebugLog = onDebugLog;

  final Future<BrowserSettings> Function() _loadSettings;
  final Future<ResolvedVideoSource> Function(String, BrowserSettings)
  _resolveVideoSource;
  final Future<void> Function(BrowserSettings) _ensureProxyServer;
  final String Function(String) _buildProxyPlaybackUrl;
  final String Function(String) _redactDownloadUrl;
  final void Function(String message)? _onDebugLog;

  Future<PreparedVideoPlayback> prepare({
    required String requestedUrl,
    required bool shouldResolveYoutube,
  }) async {
    var playbackUrl = requestedUrl;
    var downloadUrl = requestedUrl;
    var displayDownloadUrl = _redactDownloadUrl(requestedUrl);
    String? resolvedTitle;

    if (!shouldResolveYoutube) {
      return PreparedVideoPlayback(
        playbackUrl: playbackUrl,
        downloadUrl: downloadUrl,
        displayDownloadUrl: displayDownloadUrl,
      );
    }

    final settings = await _loadSettings();
    if (settings.normalizedNativeVideoParserApiBaseUrl.isEmpty) {
      throw const VideoResolutionException('请先在设置中配置 YouTube 解析接口');
    }
    final resolved = await _resolveVideoSource(requestedUrl, settings);
    final rawStreamUrl = resolved.streamUrl;
    resolvedTitle = resolved.title;
    downloadUrl = rawStreamUrl;
    displayDownloadUrl = _redactDownloadUrl(requestedUrl);

    if (settings.shouldApplyProxy) {
      await _ensureProxyServer(settings);
      playbackUrl = _buildProxyPlaybackUrl(rawStreamUrl);
      _onDebugLog?.call('VideoPlayback: proxying through $playbackUrl');
    } else {
      playbackUrl = rawStreamUrl;
    }

    return PreparedVideoPlayback(
      playbackUrl: playbackUrl,
      downloadUrl: downloadUrl,
      displayDownloadUrl: displayDownloadUrl,
      resolvedTitle: resolvedTitle,
    );
  }
}
