import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/music_track.dart';
import '../infrastructure/music_api_client.dart';
import '../infrastructure/music_library_store.dart';
import '../infrastructure/music_platform_gateway.dart';
import '../infrastructure/music_settings_store.dart';

typedef ExternalTrackOpened = Future<void> Function(MusicTrack track);

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController({
    MusicPlatformGateway? platform,
    MusicApiClient? api,
    MusicLibraryStore? library,
    MusicSettingsStore? settingsStore,
  }) : _platform = platform ?? MusicPlatformGateway.instance,
       _api = api ?? MusicApiClient(),
       _library = library ?? MusicLibraryStore.instance,
       _settingsStore = settingsStore ?? const MusicSettingsStore();

  static final MusicPlayerController instance = MusicPlayerController();

  final MusicPlatformGateway _platform;
  final MusicApiClient _api;
  final MusicLibraryStore _library;
  final MusicSettingsStore _settingsStore;

  MusicSettings _settings = const MusicSettings(
    apiBaseUrl: '',
    apiKey: '',
    quality: 'standard',
    notificationEnabled: true,
  );
  MusicTrack? _currentTrack;
  List<MusicTrack> _queue = const <MusicTrack>[];
  int _queueIndex = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completionAdvanceInProgress = false;
  String? _playbackError;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  ExternalTrackOpened? _onExternalTrackOpened;

  MusicSettings get settings => _settings;
  MusicTrack? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;
  String? get playbackError => _playbackError;
  bool get hasPrevious => _queueIndex > 0;
  bool get hasNext => _queueIndex >= 0 && _queueIndex + 1 < _queue.length;

  Future<void> initialize({ExternalTrackOpened? onExternalTrackOpened}) {
    if (onExternalTrackOpened != null) {
      _onExternalTrackOpened = onExternalTrackOpened;
    }
    final existing = _initializationFuture;
    if (existing != null) return existing;
    final future = _initializeInternal();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;
    _initialized = true;
    _platform.setHandlers(
      onPlaybackState: _handlePlaybackState,
      onExternalAudioIntent: (event) => unawaited(_handleExternalIntent(event)),
    );
    _settings = await _settingsStore.load();
    await _platform.setNotificationEnabled(_settings.notificationEnabled);
    final state = await _platform.getState();
    _handlePlaybackState(state);
    final activeTrackKey = state['trackKey']?.toString() ?? '';
    if (activeTrackKey.isNotEmpty) {
      _currentTrack = await _library.get(activeTrackKey);
    }
    final pending = await _platform.getPendingAudioIntent();
    if (pending != null && pending.isNotEmpty) {
      await _handleExternalIntent(pending);
    }
    notifyListeners();
  }

  Future<void> updateSettings(MusicSettings value) async {
    var effective = value;
    if (value.notificationEnabled && !_settings.notificationEnabled) {
      final granted = await _platform.requestNotificationPermission();
      if (!granted) {
        effective = value.copyWith(notificationEnabled: false);
      }
    }
    _settings = effective;
    await _settingsStore.save(effective);
    await _platform.setNotificationEnabled(effective.notificationEnabled);
    notifyListeners();
  }

  Future<MusicSearchPage> search(String keyword, int page) {
    return _searchAfterInitialization(keyword, page);
  }

  Future<MusicSearchPage> _searchAfterInitialization(
    String keyword,
    int page,
  ) async {
    await initialize();
    _requireApiConfiguration();
    return _api.search(
      apiBaseUrl: _settings.apiBaseUrl,
      keyword: keyword,
      page: page,
      apiKey: _settings.apiKey,
    );
  }

  Future<void> playTrack(MusicTrack track, {List<MusicTrack>? queue}) async {
    if (queue != null) {
      _queue = List<MusicTrack>.unmodifiable(queue);
      _queueIndex = _queue.indexWhere(
        (item) => item.trackKey == track.trackKey,
      );
    } else if (_queueIndex < 0 ||
        _queueIndex >= _queue.length ||
        _queue[_queueIndex].trackKey != track.trackKey) {
      _queue = <MusicTrack>[track];
      _queueIndex = 0;
    }
    _buffering = true;
    _currentTrack = track;
    notifyListeners();
    try {
      var playable = await ensurePlayable(track);
      playable = await _library.save(
        playable.copyWith(lastPlayedAt: DateTime.now()),
      );
      _currentTrack = playable;
      await _platform.play(
        uri: playable.sourceUri,
        trackKey: playable.trackKey,
        title: playable.title,
        artist: playable.artist,
        album: playable.album,
        artworkUri: playable.artworkUrl,
        notificationEnabled: _settings.notificationEnabled,
      );
    } finally {
      _buffering = false;
      notifyListeners();
    }
  }

  Future<MusicTrack> ensurePlayable(MusicTrack track) async {
    await initialize();
    if (!track.isRemote ||
        (track.sourceType != MusicSourceType.online &&
            track.sourceUri.trim().isNotEmpty)) {
      return track;
    }
    _requireApiConfiguration();
    return _api.resolve(
      apiBaseUrl: _settings.apiBaseUrl,
      track: track,
      apiKey: _settings.apiKey,
      level: _settings.quality,
    );
  }

  Future<MusicTrack> ensureLyrics(MusicTrack track) async {
    await initialize();
    final stored = await _library.get(track.trackKey) ?? track;
    if ((stored.lyric?.isNotEmpty ?? false) || !stored.isRemote) return stored;
    _requireApiConfiguration();
    final lyrics = await _api.lyrics(
      apiBaseUrl: _settings.apiBaseUrl,
      remoteId: stored.remoteId!,
      apiKey: _settings.apiKey,
    );
    final updated = await _library.save(
      stored.copyWith(
        lyric: lyrics.original ?? '[00:00.00]暂无歌词',
        translatedLyric: lyrics.translated,
      ),
    );
    if (_currentTrack?.trackKey == updated.trackKey) {
      _currentTrack = updated;
      notifyListeners();
    }
    return updated;
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) return;
    if (_playing) {
      await _platform.pause();
    } else {
      await _platform.resume();
    }
  }

  Future<void> seek(Duration position) => _platform.seek(position);

  Future<void> stop() async {
    await _platform.stop();
    _playing = false;
    _position = Duration.zero;
    _currentTrack = null;
    _queue = const <MusicTrack>[];
    _queueIndex = -1;
    notifyListeners();
  }

  Future<void> previous() async {
    if (!hasPrevious) return;
    _queueIndex--;
    await playTrack(_queue[_queueIndex]);
  }

  Future<void> next() async {
    if (!hasNext) return;
    _queueIndex++;
    await playTrack(_queue[_queueIndex]);
  }

  Future<MusicTrack> setFavorite(MusicTrack track, bool favorite) async {
    final updated = await _library.setFavorite(track, favorite);
    _replaceCurrent(updated);
    return updated;
  }

  Future<MusicTrack> setGroup(MusicTrack track, String groupName) async {
    final updated = await _library.setGroup(track, groupName);
    _replaceCurrent(updated);
    return updated;
  }

  Future<void> deleteLocalTrack(MusicTrack track) async {
    if (track.sourceType == MusicSourceType.online) {
      throw StateError('在线歌曲没有本地文件');
    }
    if (_currentTrack?.trackKey == track.trackKey) {
      await stop();
    }
    final deleted = await _platform.deleteLocalAudio(track.sourceUri);
    if (!deleted) throw StateError('未能删除歌曲文件');
    await _library.delete(track.trackKey);
  }

  void replaceCurrentTrack(MusicTrack track) => _replaceCurrent(track);

  void _replaceCurrent(MusicTrack track) {
    if (_currentTrack?.trackKey == track.trackKey) _currentTrack = track;
    notifyListeners();
  }

  void _handlePlaybackState(Map<Object?, Object?> state) {
    if (state.containsKey('trackKey') &&
        (state['trackKey']?.toString() ?? '').isEmpty) {
      _currentTrack = null;
      _queue = const <MusicTrack>[];
      _queueIndex = -1;
    }
    _playing = state['playing'] == true;
    _buffering = state['buffering'] == true;
    _position = Duration(
      milliseconds: (state['positionMs'] as num?)?.toInt() ?? 0,
    );
    _duration = Duration(
      milliseconds: (state['durationMs'] as num?)?.toInt() ?? 0,
    );
    _playbackError = state['error']?.toString();
    notifyListeners();
    if (state['completed'] != true) {
      _completionAdvanceInProgress = false;
    } else if (hasNext && !_completionAdvanceInProgress) {
      _completionAdvanceInProgress = true;
      unawaited(_advanceAfterCompletion());
    }
  }

  Future<void> _advanceAfterCompletion() async {
    try {
      await next();
    } catch (error) {
      _playbackError = '$error';
      notifyListeners();
    } finally {
      _completionAdvanceInProgress = false;
    }
  }

  Future<void> _handleExternalIntent(Map<Object?, Object?> event) async {
    final track = MusicTrack.fromPlatformMap(event);
    final saved = await _library.save(track);
    await playTrack(saved);
    await _onExternalTrackOpened?.call(saved);
  }

  void _requireApiConfiguration() {
    if (_settings.apiBaseUrl.trim().isEmpty) {
      throw StateError('请先在音乐设置中填写 API 地址');
    }
    if (_settings.apiKey.trim().isEmpty) {
      throw StateError('请先在音乐设置中填写 API Key');
    }
  }
}
