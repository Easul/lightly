import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/features/music/infrastructure/music_platform_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('music_platform_gateway_test');
  final gateway = MusicPlatformGateway(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'scanLocalMusic') {
            return <Object?>[
              <String, Object?>{'uri': 'content://song/1', 'title': '歌曲'},
            ];
          }
          return null;
        });
  });

  tearDown(() {
    gateway.setHandlers();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps playback metadata to the Android contract', () async {
    await gateway.play(
      uri: 'https://music.test/song.mp3',
      trackKey: 'online:1',
      title: '歌曲',
      artist: '歌手',
      album: '专辑',
      artworkUri: 'https://music.test/cover.jpg',
      notificationEnabled: true,
    );

    expect(calls.single.method, 'play');
    expect(calls.single.arguments, <String, Object?>{
      'uri': 'https://music.test/song.mp3',
      'trackKey': 'online:1',
      'title': '歌曲',
      'artist': '歌手',
      'album': '专辑',
      'artworkUri': 'https://music.test/cover.jpg',
      'notificationEnabled': true,
    });
  });

  test('maps MediaStore scan rows and playback events', () async {
    final rows = await gateway.scanLocalMusic();
    expect(rows.single['uri'], 'content://song/1');

    final received = Completer<Map<Object?, Object?>>();
    gateway.setHandlers(onPlaybackState: received.complete);
    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onPlaybackState', <String, Object?>{
        'playing': true,
        'positionMs': 1500,
      }),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, message, (_) {});

    expect((await received.future)['playing'], isTrue);
  });
}
