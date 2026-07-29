import '../../features/video/application/video_playback_preparation_service.dart';
import '../../features/video/application/video_playback_preparer.dart';
import '../../features/video/domain/video_source_resolver.dart';
import '../browser_settings.dart';

class BrowserVideoPlaybackPreparationService implements VideoPlaybackPreparer {
  BrowserVideoPlaybackPreparationService({
    required Future<BrowserSettings> Function() loadSettings,
    required Future<ResolvedVideoSource> Function(String, BrowserSettings)
    resolveVideoSource,
    required Future<void> Function(BrowserSettings) ensureProxyServer,
    required String Function(String, Map<String, String>?)
    buildProxyPlaybackUrl,
    required String Function(String) redactDownloadUrl,
    void Function(String message)? onDebugLog,
  }) : _delegate = VideoPlaybackPreparationService<BrowserSettings>(
         loadSettings: loadSettings,
         isParserConfigured: (settings) => settings.nativeVideoPlayerEnabled,
         resolveVideoSource: resolveVideoSource,
         ensureProxyServer: ensureProxyServer,
         buildProxyPlaybackUrl: buildProxyPlaybackUrl,
         redactDownloadUrl: redactDownloadUrl,
         onDebugLog: onDebugLog,
       );

  final VideoPlaybackPreparationService<BrowserSettings> _delegate;

  @override
  Future<PreparedVideoPlayback> prepare({
    required String requestedUrl,
    required bool shouldResolveYoutube,
  }) {
    return _delegate.prepare(
      requestedUrl: requestedUrl,
      shouldResolveYoutube: shouldResolveYoutube,
    );
  }
}
