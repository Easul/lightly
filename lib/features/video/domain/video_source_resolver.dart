/// Neutral resolved video source model used by the native player.
class ResolvedVideoSource {
  const ResolvedVideoSource({
    required this.videoId,
    required this.title,
    required this.streamUrl,
    this.httpHeaders,
  });

  final String videoId;
  final String title;
  final String streamUrl;
  final Map<String, String>? httpHeaders;
}

/// Exception thrown when video resolution fails.
class VideoResolutionException implements Exception {
  const VideoResolutionException(this.message);

  final String message;

  @override
  String toString() => 'VideoResolutionException: $message';
}

/// Contract for resolving a video URL into a direct playable stream.
abstract class VideoSourceResolver {
  const VideoSourceResolver();

  /// Resolves [url] into a direct playable video source.
  ///
  /// Throws [VideoResolutionException] when resolution is not possible.
  Future<ResolvedVideoSource> resolve(String url);
}
