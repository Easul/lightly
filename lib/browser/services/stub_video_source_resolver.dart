import '../../features/video/domain/youtube_long_press_utils.dart';
import '../../features/video/domain/video_source_resolver.dart';

/// Stub resolver that rejects all YouTube URLs until an external API is configured.
///
/// This replaces the previous youtube_explode_dart-based resolver.
/// When the external API is available, implement [VideoSourceResolver] and
/// inject it into [NativeVideoPlayerPage].
class StubVideoSourceResolver extends VideoSourceResolver {
  const StubVideoSourceResolver();

  @override
  Future<ResolvedVideoSource> resolve(String url) async {
    final targets = deriveYouTubeLongPressTargets(url);
    final videoId = targets?.videoId;
    if (videoId == null || videoId.isEmpty) {
      throw const VideoResolutionException('Unsupported video URL');
    }
    throw const VideoResolutionException(
      'YouTube resolver not configured. '
      'Please provide an external API endpoint.',
    );
  }
}
