import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/video/domain/video_source_resolver.dart';
import 'package:lightly/features/video/infrastructure/youtube_resolver_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('youtube_resolver_gateway_test');
  const gateway = YouTubeResolverPlatformGateway(
    channel: channel,
    proxyRoute: 'PROXY 127.0.0.1:23333',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps AAR availability metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'availability');
          return <String, Object?>{'available': true, 'apiVersion': 1};
        });

    final availability = await gateway.availability();

    expect(availability.available, isTrue);
    expect(availability.apiVersion, 1);
  });

  test('maps native resolver payload and proxy route', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return jsonEncode(<String, Object?>{
            'videoId': 'abc123',
            'title': 'Example',
            'streamUrl': 'https://rr1.googlevideo.com/videoplayback?id=abc123',
            'httpHeaders': <String, String>{
              'cookie': 'SID=secret',
              'referer': 'https://m.youtube.com/',
            },
          });
        });

    final resolved = await gateway.resolve(
      'https://www.youtube.com/watch?v=abc123',
    );

    expect(capturedCall?.method, 'resolve');
    expect(capturedCall?.arguments, <String, Object?>{
      'url': 'https://www.youtube.com/watch?v=abc123',
      'proxyRoute': 'PROXY 127.0.0.1:23333',
    });
    expect(resolved.videoId, 'abc123');
    expect(resolved.title, 'Example');
    expect(resolved.httpHeaders?['cookie'], 'SID=secret');
  });

  test('surfaces unavailable AAR as a video resolution error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'UNAVAILABLE',
            message: '当前安装包未包含 YouTube 解析组件',
          );
        });

    await expectLater(
      gateway.resolve('https://youtu.be/abc123'),
      throwsA(
        isA<VideoResolutionException>().having(
          (error) => error.message,
          'message',
          '当前安装包未包含 YouTube 解析组件',
        ),
      ),
    );
  });
}
