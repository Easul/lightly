import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/music_track.dart';
import '../infrastructure/music_api_client.dart';
import '../infrastructure/music_library_store.dart';
import '../infrastructure/music_platform_gateway.dart';
import '../infrastructure/music_settings_store.dart';

typedef ExternalTrackOpened = Future<void> Function(MusicTrack track);

enum MusicPlaybackMode { listLoop, singleLoop, shuffle }

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
  List<MusicTrack> _downloadedQueue = const <MusicTrack>[];
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
  MusicPlaybackMode _playbackMode = MusicPlaybackMode.listLoop;
  String _searchKeyword = '';
  List<MusicTrack> _searchResults = const <MusicTrack>[];
  int _searchPage = 0;
  int _searchTotal = 0;
  bool _searching = false;
  bool _searchHasMore = false;
  String? _searchError;
  int _searchRequestId = 0;
  bool _playbackCommandInProgress = false;
  final Random _random = Random();
  final ValueNotifier<int> _searchRevision = ValueNotifier<int>(0);
  final ValueNotifier<String?> _activeTrackKey = ValueNotifier<String?>(null);

  MusicSettings get settings => _settings;
  MusicTrack? get currentTrack => _currentTrack;
  List<MusicTrack> get downloadedQueue => _downloadedQueue;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;
  String? get playbackError => _playbackError;
  MusicPlaybackMode get playbackMode => _playbackMode;
  bool get hasPrevious => _queue.length > 1;
  bool get hasNext => _queue.length > 1;
  String get searchKeyword => _searchKeyword;
  List<MusicTrack> get searchResults => _searchResults;
  int get searchTotal => _searchTotal;
  bool get isSearching => _searching;
  bool get searchHasMore => _searchHasMore;
  String? get searchError => _searchError;
  ValueListenable<int> get searchChanges => _searchRevision;
  ValueListenable<String?> get activeTrackKeyChanges => _activeTrackKey;

  String get playbackModeLabel => switch (_playbackMode) {
    MusicPlaybackMode.listLoop => '列表循环',
    MusicPlaybackMode.singleLoop => '单曲循环',
    MusicPlaybackMode.shuffle => '随机播放',
  };

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
      onPlaybackCommand: (command) =>
          unawaited(_handlePlaybackCommand(command)),
      onExternalAudioIntent: (event) => unawaited(_handleExternalIntent(event)),
    );
    _settings = await _settingsStore.load();
    await _platform.setNotificationEnabled(_settings.notificationEnabled);
    _downloadedQueue = await _buildDownloadedQueue();
    final state = await _platform.getState();
    _handlePlaybackState(state);
    final activeTrackKey = state['trackKey']?.toString() ?? '';
    if (activeTrackKey.isNotEmpty) {
      _setCurrentTrack(await _library.get(activeTrackKey));
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

  Future<void> search(String keyword) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) return;
    final requestId = ++_searchRequestId;
    _searchKeyword = normalized;
    _searchResults = const <MusicTrack>[];
    _searchPage = 0;
    _searchTotal = 0;
    _searchHasMore = true;
    _searchError = null;
    _searching = true;
    _notifySearchChanged();
    try {
      await _loadSearchPage(requestId: requestId, page: 1, append: false);
    } catch (error) {
      if (requestId == _searchRequestId) {
        _searchError = '$error';
      }
      rethrow;
    } finally {
      if (requestId == _searchRequestId) {
        _searching = false;
        _notifySearchChanged();
      }
    }
  }

  Future<void> loadMoreSearchResults() async {
    if (_searching || !_searchHasMore || _searchKeyword.isEmpty) return;
    final requestId = _searchRequestId;
    _searching = true;
    _searchError = null;
    _notifySearchChanged();
    try {
      await _loadSearchPage(
        requestId: requestId,
        page: _searchPage + 1,
        append: true,
      );
    } catch (error) {
      if (requestId == _searchRequestId) {
        _searchError = '$error';
      }
      rethrow;
    } finally {
      if (requestId == _searchRequestId) {
        _searching = false;
        _notifySearchChanged();
      }
    }
  }

  Future<void> _loadSearchPage({
    required int requestId,
    required int page,
    required bool append,
  }) async {
    await initialize();
    _requireApiConfiguration();
    final result = await _api.search(
      apiBaseUrl: _settings.apiBaseUrl,
      keyword: _searchKeyword,
      page: page,
      apiKey: _settings.apiKey,
    );
    final tracks = result.tracks;
    if (requestId != _searchRequestId) return;
    final merged = append ? <MusicTrack>[..._searchResults, ...tracks] : tracks;
    _searchResults = List<MusicTrack>.unmodifiable(
      <String, MusicTrack>{
        for (final track in merged) track.trackKey: track,
      }.values,
    );
    _searchPage = page;
    _searchTotal = result.total;
    _searchHasMore = result.hasMore;
    updateActiveQueue(_searchResults);
    _notifySearchChanged();
  }

  void clearSearch() {
    _searchRequestId++;
    _searchKeyword = '';
    _searchResults = const <MusicTrack>[];
    _searchPage = 0;
    _searchTotal = 0;
    _searchHasMore = false;
    _searchError = null;
    _searching = false;
    _notifySearchChanged();
  }

  void updateActiveQueue(List<MusicTrack> tracks) {
    final currentKey = _currentTrack?.trackKey;
    if (currentKey == null ||
        !_queue.any((track) => track.trackKey == currentKey)) {
      return;
    }
    final nextIndex = tracks.indexWhere(
      (track) => track.trackKey == currentKey,
    );
    if (nextIndex < 0) return;
    _queue = List<MusicTrack>.unmodifiable(tracks);
    _queueIndex = nextIndex;
  }

  Future<void> playTrack(MusicTrack track, {List<MusicTrack>? queue}) async {
    if (queue != null) {
      _queue = List<MusicTrack>.unmodifiable(queue);
      _queueIndex = _queue.indexWhere(
        (item) => item.trackKey == track.trackKey,
      );
      if (_queueIndex < 0 && _queue.isNotEmpty) _queueIndex = 0;
    } else if (_queueIndex < 0 ||
        _queueIndex >= _queue.length ||
        _queue[_queueIndex].trackKey != track.trackKey) {
      _queue = <MusicTrack>[track];
      _queueIndex = 0;
    }
    _buffering = true;
    final isLocalDevice =
        track.sourceType == MusicSourceType.local && track.localPath != null;
    if (!isLocalDevice) {
      _setCurrentTrack(track);
    }
    notifyListeners();
    try {
      var playable = await ensurePlayable(track);
      if (isLocalDevice) {
        playable = playable.copyWith(lastPlayedAt: DateTime.now());
      } else {
        playable = await _library.save(
          playable.copyWith(lastPlayedAt: DateTime.now()),
        );
      }
      _replaceDownloadedQueueTrack(playable);
      _setCurrentTrack(playable);
      _replaceQueuedTrack(playable);
      _replaceSearchTrack(playable);
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
    if (!track.isRemote &&
        track.localPath != null &&
        track.sourceUri.startsWith('file://')) {
      final contentUri = await _resolveMediaStoreUri(track.localPath!);
      if (contentUri != null && contentUri != track.sourceUri) {
        return track.copyWith(sourceUri: contentUri);
      }
      return track;
    }
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

  Future<String?> _resolveMediaStoreUri(String path) async {
    try {
      await _platform.markLocalTrackPlayed(path);
      final metadata = await _platform.resolveLocalMetadata(path);
      final uri = metadata?['uri']?.toString().trim();
      if (uri == null || uri.isEmpty) return null;
      return uri;
    } on Object catch (error) {
      debugPrint('[Music] resolve MediaStore uri failed: $error');
      return null;
    }
  }

  Future<MusicTrack> ensureLyrics(MusicTrack track) async {
    await initialize();
    final stored = track.lyric != null
        ? track
        : await _library.get(track.trackKey) ?? track;
    if ((stored.lyric?.isNotEmpty ?? false) || !stored.isRemote) {
      return stored;
    }
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
    _setCurrentTrack(null);
    _queue = const <MusicTrack>[];
    _queueIndex = -1;
    notifyListeners();
  }

  void detachQueue() {
    _queue = const <MusicTrack>[];
    _queueIndex = -1;
  }

  void cyclePlaybackMode() {
    _playbackMode = switch (_playbackMode) {
      MusicPlaybackMode.listLoop => MusicPlaybackMode.singleLoop,
      MusicPlaybackMode.singleLoop => MusicPlaybackMode.shuffle,
      MusicPlaybackMode.shuffle => MusicPlaybackMode.listLoop,
    };
    notifyListeners();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_playbackMode == MusicPlaybackMode.shuffle && _queue.length > 1) {
      _queueIndex = _randomIndex();
    } else {
      _queueIndex = (_queueIndex - 1 + _queue.length) % _queue.length;
    }
    await playTrack(_queue[_queueIndex]);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_playbackMode == MusicPlaybackMode.singleLoop) {
      await playTrack(_queue[_queueIndex]);
      return;
    }
    if (_playbackMode == MusicPlaybackMode.shuffle && _queue.length > 1) {
      _queueIndex = _randomIndex();
    } else {
      _queueIndex = (_queueIndex + 1) % _queue.length;
    }
    await playTrack(_queue[_queueIndex]);
  }

  int _randomIndex() {
    var index = _random.nextInt(_queue.length);
    while (index == _queueIndex && _queue.length > 1) {
      index = _random.nextInt(_queue.length);
    }
    return index;
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
    if (_currentTrack?.trackKey == track.trackKey) _setCurrentTrack(track);
    _replaceQueuedTrack(track);
    _replaceSearchTrack(track);
    _replaceDownloadedQueueTrack(track);
    notifyListeners();
  }

  Future<void> registerDownloadedTrack(MusicTrack track) async {
    final stored = await _library.get(track.trackKey);
    if (stored != null &&
        stored.lyric == null &&
        track.lyric != null &&
        stored.sourceUri != track.sourceUri) {
      final pruned = stored.copyWith(lyric: '', translatedLyric: '');
      await _library.save(pruned);
      _replaceDownloadedQueueTrack(pruned);
    } else {
      _replaceDownloadedQueueTrack(stored ?? track);
    }
    notifyListeners();
  }

  Future<List<MusicTrack>> _buildDownloadedQueue() async {
    final downloaded = await _library.list(
      sourceType: MusicSourceType.downloaded,
    );
    downloaded.sort(
      (a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );
    final seenPaths = <String>{};
    final queue = <MusicTrack>[];
    for (final track in downloaded) {
      final path = track.localPath;
      if (path == null || !seenPaths.add(path)) continue;
      final localKey = 'local:$path';
      final scanned = await _library.get(localKey);
      queue.add(
        scanned?.copyWith(
              lyric: track.lyric,
              translatedLyric: track.translatedLyric,
              artworkUrl: track.artworkUrl ?? scanned.artworkUrl,
            ) ??
            track,
      );
    }
    return List<MusicTrack>.unmodifiable(queue);
  }

  void _replaceDownloadedQueueTrack(MusicTrack track) {
    final path = track.localPath;
    if (path == null) return;
    final index = _downloadedQueue.indexWhere((item) => item.localPath == path);
    if (index < 0) return;
    final updated = _downloadedQueue.toList(growable: false);
    final existing = updated[index];
    updated[index] = track.copyWith(
      lyric: existing.lyric ?? track.lyric,
      translatedLyric: existing.translatedLyric ?? track.translatedLyric,
    );
    _downloadedQueue = List<MusicTrack>.unmodifiable(updated);
  }

  void _handlePlaybackState(Map<Object?, Object?> state) {
    if (state.containsKey('trackKey') &&
        (state['trackKey']?.toString() ?? '').isEmpty) {
      _setCurrentTrack(null);
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
    } else if (_queue.isNotEmpty && !_completionAdvanceInProgress) {
      _completionAdvanceInProgress = true;
      unawaited(_advanceAfterCompletion());
    }
  }

  Future<void> _handlePlaybackCommand(String command) async {
    if (_playbackCommandInProgress || _queue.isEmpty) return;
    _playbackCommandInProgress = true;
    try {
      if (command == 'previous' && hasPrevious) {
        await previous();
      } else if (command == 'next' && hasNext) {
        await next();
      }
    } finally {
      _playbackCommandInProgress = false;
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
    final path = track.localPath;
    if (track.sourceType == MusicSourceType.local &&
        path != null &&
        path.isNotEmpty) {
      await playTrack(track);
      await _onExternalTrackOpened?.call(track);
      return;
    }
    final saved = await _library.save(track);
    await playTrack(saved);
    await _onExternalTrackOpened?.call(saved);
  }

  void _requireApiConfiguration() {
    debugPrint(
      '[MusicSearch] config basePresent=${_settings.apiBaseUrl.trim().isNotEmpty} '
      'keyPresent=${_settings.apiKey.trim().isNotEmpty}',
    );
    if (_settings.apiBaseUrl.trim().isEmpty) {
      throw StateError('请先在音乐设置中填写 API 地址');
    }
    if (_settings.apiKey.trim().isEmpty) {
      throw StateError('请先在音乐设置中填写 API Key');
    }
  }

  void _setCurrentTrack(MusicTrack? track) {
    _currentTrack = track;
    final key = track?.trackKey;
    if (_activeTrackKey.value != key) _activeTrackKey.value = key;
  }

  void _replaceQueuedTrack(MusicTrack track) {
    final index = _queue.indexWhere((item) => item.trackKey == track.trackKey);
    if (index < 0) return;
    final updated = _queue.toList(growable: false);
    updated[index] = track;
    _queue = List<MusicTrack>.unmodifiable(updated);
  }

  void _replaceSearchTrack(MusicTrack track) {
    if (!_searchResults.any((item) => item.trackKey == track.trackKey)) return;
    _searchResults = _searchResults
        .map((item) => item.trackKey == track.trackKey ? track : item)
        .toList(growable: false);
    _notifySearchChanged();
  }

  void _notifySearchChanged() {
    _searchRevision.value++;
  }

  @override
  void dispose() {
    _searchRevision.dispose();
    _activeTrackKey.dispose();
    super.dispose();
  }
}
