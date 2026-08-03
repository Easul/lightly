import 'package:flutter/services.dart';

typedef MusicPlaybackEventHandler = void Function(Map<Object?, Object?> event);
typedef ExternalMusicIntentHandler = void Function(Map<Object?, Object?> event);

class MusicPlatformGateway {
  MusicPlatformGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'lightly_music_player';
  static final MusicPlatformGateway instance = MusicPlatformGateway();

  final MethodChannel _channel;

  void setHandlers({
    MusicPlaybackEventHandler? onPlaybackState,
    ExternalMusicIntentHandler? onExternalAudioIntent,
  }) {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (arguments is! Map) return;
      if (call.method == 'onPlaybackState') {
        onPlaybackState?.call(arguments);
      } else if (call.method == 'onExternalAudioIntent') {
        onExternalAudioIntent?.call(arguments);
      }
    });
  }

  Future<List<Map<Object?, Object?>>> scanLocalMusic() async {
    final result = await _channel.invokeListMethod<Object?>('scanLocalMusic');
    return (result ?? const <Object?>[])
        .whereType<Map>()
        .cast<Map<Object?, Object?>>()
        .toList(growable: false);
  }

  Future<bool> deleteLocalAudio(String uri) async {
    return await _channel.invokeMethod<bool>(
          'deleteLocalAudio',
          <String, Object?>{'uri': uri},
        ) ??
        false;
  }

  Future<bool> hasAudioPermission() async {
    return await _channel.invokeMethod<bool>('hasAudioPermission') ?? false;
  }

  Future<bool> requestAudioPermission() async {
    return await _channel.invokeMethod<bool>('requestAudioPermission') ?? false;
  }

  Future<bool> requestNotificationPermission() async {
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  }

  Future<void> play({
    required String uri,
    required String trackKey,
    required String title,
    required String artist,
    required String album,
    String? artworkUri,
    required bool notificationEnabled,
  }) {
    return _channel.invokeMethod<void>('play', <String, Object?>{
      'uri': uri,
      'trackKey': trackKey,
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUri': artworkUri,
      'notificationEnabled': notificationEnabled,
    });
  }

  Future<void> resume() => _channel.invokeMethod<void>('resume');
  Future<void> pause() => _channel.invokeMethod<void>('pause');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> seek(Duration position) => _channel.invokeMethod<void>(
    'seekTo',
    <String, Object?>{'positionMs': position.inMilliseconds},
  );

  Future<void> setNotificationEnabled(bool enabled) {
    return _channel.invokeMethod<void>(
      'setNotificationEnabled',
      <String, Object?>{'enabled': enabled},
    );
  }

  Future<Map<Object?, Object?>> getState() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('getState');
    return result ?? const <Object?, Object?>{};
  }

  Future<Map<Object?, Object?>?> getPendingAudioIntent() {
    return _channel.invokeMapMethod<Object?, Object?>('getPendingAudioIntent');
  }
}
