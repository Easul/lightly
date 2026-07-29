import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/video_source_resolver.dart';

class YouTubeResolverAvailability {
  const YouTubeResolverAvailability({
    required this.available,
    required this.apiVersion,
  });

  final bool available;
  final int? apiVersion;
}

class YouTubeResolverPlatformGateway extends VideoSourceResolver {
  const YouTubeResolverPlatformGateway({
    this.proxyRoute = 'DIRECT',
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'youtube_resolver';

  final String proxyRoute;
  final MethodChannel _channel;

  Future<YouTubeResolverAvailability> availability() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'availability',
    );
    return YouTubeResolverAvailability(
      available: value?['available'] == true,
      apiVersion: (value?['apiVersion'] as num?)?.toInt(),
    );
  }

  @override
  Future<ResolvedVideoSource> resolve(String url) async {
    try {
      final payload = await _channel.invokeMethod<String>(
        'resolve',
        <String, Object?>{'url': url, 'proxyRoute': proxyRoute},
      );
      if (payload == null || payload.isEmpty) {
        throw const VideoResolutionException('YouTube 解析组件返回空结果');
      }
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const VideoResolutionException('YouTube 解析组件返回格式错误');
      }
      final videoId = decoded['videoId'] as String? ?? '';
      final title = decoded['title'] as String? ?? '';
      final streamUrl = decoded['streamUrl'] as String? ?? '';
      if (videoId.isEmpty || streamUrl.isEmpty) {
        throw const VideoResolutionException('YouTube 解析组件未返回可播放地址');
      }
      final rawHeaders = decoded['httpHeaders'];
      final headers = rawHeaders is Map
          ? <String, String>{
              for (final entry in rawHeaders.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : null;
      return ResolvedVideoSource(
        videoId: videoId,
        title: title.isEmpty ? videoId : title,
        streamUrl: streamUrl,
        httpHeaders: headers?.isEmpty == true ? null : headers,
      );
    } on PlatformException catch (error) {
      throw VideoResolutionException(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'YouTube 解析组件不可用',
      );
    } on FormatException {
      throw const VideoResolutionException('YouTube 解析组件返回格式错误');
    }
  }
}
