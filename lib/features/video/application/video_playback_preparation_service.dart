import '../domain/video_source_resolver.dart';
import 'video_playback_preparer.dart';

class VideoPlaybackPreparationService<TSettings>
    implements VideoPlaybackPreparer {
  VideoPlaybackPreparationService({
    required Future<TSettings> Function() loadSettings,
    required bool Function(TSettings) isParserConfigured,
    required Future<ResolvedVideoSource> Function(String, TSettings)
    resolveVideoSource,
    required Future<void> Function(TSettings) ensureProxyServer,
    required String Function(String, Map<String, String>?)
    buildProxyPlaybackUrl,
    required String Function(String) redactDownloadUrl,
    void Function(String message)? onDebugLog,
  }) : _loadSettings = loadSettings,
       _isParserConfigured = isParserConfigured,
       _resolveVideoSource = resolveVideoSource,
       _ensureProxyServer = ensureProxyServer,
       _buildProxyPlaybackUrl = buildProxyPlaybackUrl,
       _redactDownloadUrl = redactDownloadUrl,
       _onDebugLog = onDebugLog;

  final Future<TSettings> Function() _loadSettings;
  final bool Function(TSettings) _isParserConfigured;
  final Future<ResolvedVideoSource> Function(String, TSettings)
  _resolveVideoSource;
  final Future<void> Function(TSettings) _ensureProxyServer;
  final String Function(String, Map<String, String>?) _buildProxyPlaybackUrl;
  final String Function(String) _redactDownloadUrl;
  final void Function(String message)? _onDebugLog;

  @override
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
    if (!_isParserConfigured(settings)) {
      throw const VideoResolutionException('请先在设置中配置 YouTube 解析接口');
    }
    final resolved = await _resolveVideoSource(requestedUrl, settings);
    final rawStreamUrl = resolved.streamUrl;
    resolvedTitle = resolved.title;
    downloadUrl = rawStreamUrl;
    displayDownloadUrl = _redactDownloadUrl(requestedUrl);
    final downloadHeaders = resolved.httpHeaders;

    await _ensureProxyServer(settings);
    playbackUrl = _buildProxyPlaybackUrl(rawStreamUrl, downloadHeaders);
    _onDebugLog?.call('VideoPlayback: using local proxy');

    return PreparedVideoPlayback(
      playbackUrl: playbackUrl,
      downloadUrl: downloadUrl,
      displayDownloadUrl: displayDownloadUrl,
      resolvedTitle: resolvedTitle,
      downloadHeaders: downloadHeaders,
    );
  }
}
