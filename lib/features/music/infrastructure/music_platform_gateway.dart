import 'package:flutter/services.dart';

typedef MusicPlaybackEventHandler = void Function(Map<Object?, Object?> event);
typedef MusicPlaybackCommandHandler = void Function(String command);
typedef ExternalMusicIntentHandler = void Function(Map<Object?, Object?> event);
typedef MusicNotificationOpenHandler = void Function();

class MusicPlatformGateway {
  MusicPlatformGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'lightly_music_player';
  static final MusicPlatformGateway instance = MusicPlatformGateway();

  final MethodChannel _channel;

  void setHandlers({
    MusicPlaybackEventHandler? onPlaybackState,
    MusicPlaybackCommandHandler? onPlaybackCommand,
    ExternalMusicIntentHandler? onExternalAudioIntent,
    MusicNotificationOpenHandler? onNotificationOpen,
  }) {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (arguments is! Map) return;
      if (call.method == 'onPlaybackState') {
        onPlaybackState?.call(arguments);
      } else if (call.method == 'onPlaybackCommand') {
        final command = arguments['command']?.toString();
        if (command != null) onPlaybackCommand?.call(command);
      } else if (call.method == 'onExternalAudioIntent') {
        onExternalAudioIntent?.call(arguments);
      } else if (call.method == 'onNotificationOpen') {
        onNotificationOpen?.call();
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

  Future<void> markLocalTrackPlayed(String path) {
    return _channel.invokeMethod<void>(
      'markLocalTrackPlayed',
      <String, Object?>{'path': path},
    );
  }

  Future<Map<Object?, Object?>?> resolveLocalMetadata(String path) {
    return _channel.invokeMapMethod<Object?, Object?>(
      'resolveLocalMetadata',
      <String, Object?>{'path': path},
    );
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
    int startPositionMs = 0,
    required bool notificationEnabled,
  }) {
    return _channel.invokeMethod<void>('play', <String, Object?>{
      'uri': uri,
      'trackKey': trackKey,
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUri': artworkUri,
      'positionMs': startPositionMs,
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
