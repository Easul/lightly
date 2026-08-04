import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/music_library_sort.dart';
import '../domain/music_track.dart';
import '../infrastructure/music_api_client.dart';
import '../infrastructure/music_library_store.dart';
import '../infrastructure/music_platform_gateway.dart';
import '../infrastructure/music_settings_store.dart';

typedef ExternalTrackOpened = Future<void> Function(MusicTrack track);

/// Decides how the app reacts when the system playback notification opens it.
typedef MusicNotificationOpened = Future<void> Function(MusicTrack? track);

enum MusicPlaybackMode { listLoop, singleLoop, shuffle }

/// A request to resume a track from its remembered playback position. Pages
/// surface this as a confirmation dialog and answer through
/// [MusicPlayerController.resolveResumeRequest].
class MusicResumeRequest {
  const MusicResumeRequest({
    required this.track,
    required this.position,
    required this.queue,
  });

  final MusicTrack track;
  final Duration position;
  final List<MusicTrack> queue;
}

class _PendingPlay {
  const _PendingPlay({required this.track, required this.queue, this.startAt});

  final MusicTrack track;
  final List<MusicTrack> queue;
  final Duration? startAt;
}

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
  List<MusicTrack> _lastBrowseQueue = const <MusicTrack>[];
  int _queueIndex = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _hasPlaybackSession = false;
  bool _completionAdvanceInProgress = false;
  String? _playbackError;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  ExternalTrackOpened? _onExternalTrackOpened;
  MusicNotificationOpened? _onNotificationOpened;
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
  bool _positionSaveQueued = false;
  _PendingPlay? _pendingPlay;
  final Random _random = Random();
  final ValueNotifier<int> _searchRevision = ValueNotifier<int>(0);
  final ValueNotifier<String?> _activeTrackKey = ValueNotifier<String?>(null);
  final ValueNotifier<MusicResumeRequest?> _resumeRequest =
      ValueNotifier<MusicResumeRequest?>(null);

  MusicSettings get settings => _settings;
  MusicTrack? get currentTrack => _currentTrack;
  List<MusicTrack> get queue => _queue;
  List<MusicTrack> get downloadedQueue => _downloadedQueue;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _playing;
  bool get isBuffering => _buffering;
  String? get playbackError => _playbackError;
  MusicPlaybackMode get playbackMode => _playbackMode;
  bool get hasPrevious => _effectiveQueue.length > 1;
  bool get hasNext => _effectiveQueue.length > 1;
  String get searchKeyword => _searchKeyword;
  List<MusicTrack> get searchResults => _searchResults;
  int get searchTotal => _searchTotal;
  bool get isSearching => _searching;
  bool get searchHasMore => _searchHasMore;
  String? get searchError => _searchError;
  ValueListenable<int> get searchChanges => _searchRevision;
  ValueListenable<String?> get activeTrackKeyChanges => _activeTrackKey;
  ValueListenable<MusicResumeRequest?> get resumeRequestChanges =>
      _resumeRequest;

  List<MusicTrack> get _effectiveQueue =>
      _queue.isNotEmpty ? _queue : _lastBrowseQueue;

  int get _effectiveIndex {
    final queue = _effectiveQueue;
    if (queue.isEmpty) return -1;
    final currentKey = _currentTrack?.trackKey;
    if (currentKey != null) {
      final index = queue.indexWhere((track) => track.trackKey == currentKey);
      if (index >= 0) return index;
    }
    if (currentKey == null) {
      final queued = _queueIndex;
      if (queued >= 0 && queued < queue.length) return queued;
    }
    return 0;
  }

  String get playbackModeLabel => switch (_playbackMode) {
    MusicPlaybackMode.listLoop => '列表循环',
    MusicPlaybackMode.singleLoop => '单曲循环',
    MusicPlaybackMode.shuffle => '随机播放',
  };

  Future<void> initialize({
    ExternalTrackOpened? onExternalTrackOpened,
    MusicNotificationOpened? onNotificationOpened,
  }) {
    if (onExternalTrackOpened != null) {
      _onExternalTrackOpened = onExternalTrackOpened;
    }
    if (onNotificationOpened != null) {
      _onNotificationOpened = onNotificationOpened;
    }
    final existing = _initializationFuture;
    if (existing != null) return existing;
    final future = _initializeInternal();
    _initializationFuture = future;
    return future;
  }

  /// Handles a tap on the system playback notification: resolves any pending
  /// resume request by continuing from the saved position, then routes the
  /// app to the music page.
  Future<void> handleNotificationOpen() async {
    await initialize();
    final hadPending = _pendingPlay != null;
    await resumePendingFromSaved();
    await _onNotificationOpened?.call(hadPending ? null : _currentTrack);
  }

  Future<void> _initializeInternal() async {
    if (_initialized) return;
    _initialized = true;
    _platform.setHandlers(
      onPlaybackState: _handlePlaybackState,
      onPlaybackCommand: (command) =>
          unawaited(_handlePlaybackCommand(command)),
      onExternalAudioIntent: (event) => unawaited(_handleExternalIntent(event)),
      onNotificationOpen: () => unawaited(handleNotificationOpen()),
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

  Future<void> setLibrarySort(MusicLibrarySort sort) {
    return updateSettings(_settings.copyWith(librarySort: sort));
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

  /// Remembers the most recently browsed local/favorite list so that
  /// previous/next still work before any track has started playing.
  void registerBrowseQueue(List<MusicTrack> tracks) {
    _lastBrowseQueue = List<MusicTrack>.unmodifiable(tracks);
  }

  Future<void> playTrack(
    MusicTrack track, {
    List<MusicTrack>? queue,
    Duration? startAt,
    bool savePosition = true,
  }) async {
    if (savePosition) {
      await _persistCurrentPosition();
    }
    if (queue != null) {
      _queue = List<MusicTrack>.unmodifiable(queue);
      _lastBrowseQueue = _queue;
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
    if (startAt != null && startAt > Duration.zero) {
      _position = startAt;
    }
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
        startPositionMs: startAt?.inMilliseconds ?? 0,
        notificationEnabled: _settings.notificationEnabled,
      );
    } finally {
      _buffering = false;
      notifyListeners();
    }
  }

  /// Starts the tapped track immediately unless it already finished once and
  /// has a remembered position; in that case a resume request is surfaced so
  /// the page can ask whether to continue from that position.
  Future<void> playFromLibrary(MusicTrack track, List<MusicTrack> queue) async {
    final stored = await _library.get(track.trackKey);
    final candidate = stored ?? track;
    final positionMs = candidate.lastPositionMs;
    final durationMs = candidate.durationMs;
    final nearEnd = durationMs > 0 && positionMs >= durationMs - 5000;
    if (_settings.resumePromptEnabled &&
        positionMs >= 10000 &&
        candidate.lastPlayedAt != null &&
        !nearEnd) {
      _pendingPlay = _PendingPlay(
        track: candidate,
        queue: List<MusicTrack>.unmodifiable(queue),
        startAt: Duration(milliseconds: positionMs),
      );
      _resumeRequest.value = MusicResumeRequest(
        track: candidate,
        position: Duration(milliseconds: positionMs),
        queue: List<MusicTrack>.unmodifiable(queue),
      );
      return;
    }
    await playTrack(candidate, queue: queue);
  }

  Future<void> resolveResumeRequest(bool resumeFromSaved) async {
    final pending = _pendingPlay;
    _pendingPlay = null;
    _resumeRequest.value = null;
    if (pending == null) return;
    await playTrack(
      pending.track,
      queue: pending.queue,
      startAt: resumeFromSaved ? pending.startAt : null,
      // The decision to resume or restart is explicit; do not let the
      // pre-switch position save wipe the remembered value for this play.
      savePosition: !resumeFromSaved,
    );
  }

  /// Drops a pending resume request without starting playback. The playback
  /// detail page consumes the remembered position itself when the user chose
  /// to resume.
  void discardResumeRequest() {
    _pendingPlay = null;
    _resumeRequest.value = null;
  }

  /// Resolves the current resume request by starting playback from the
  /// remembered position (used when the system notification opens the player).
  Future<void> resumePendingFromSaved() async {
    final pending = _pendingPlay;
    discardResumeRequest();
    if (pending == null) return;
    await playTrack(
      pending.track,
      queue: pending.queue,
      startAt: pending.startAt,
      savePosition: false,
    );
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
    var stored = track.lyric != null
        ? track
        : await _library.get(track.trackKey) ?? track;
    if (stored.lyric == null && stored.isRemote) {
      final mediaStoreMatch = await _findScannedMatch(stored);
      if (mediaStoreMatch?.lyric?.isNotEmpty ?? false) {
        stored = mediaStoreMatch!;
      }
    }
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
    if (updated.lyric?.isNotEmpty ?? false) {
      final localMatch = await _findScannedMatch(updated);
      if (localMatch != null && localMatch.lyric == null) {
        final mirrored = await _library.save(
          localMatch.copyWith(
            lyric: updated.lyric,
            translatedLyric: updated.translatedLyric,
          ),
        );
        _replaceQueuedTrack(mirrored);
        _replaceDownloadedQueueTrack(mirrored);
      }
    }
    if (_currentTrack?.trackKey == updated.trackKey) {
      _currentTrack = updated;
      notifyListeners();
    }
    return updated;
  }

  /// Finds the scanned local row that points at the same file as a downloaded
  /// (remote-id keyed) track, so lyrics cached during local playback can be
  /// reused when the downloaded row is opened again.
  Future<MusicTrack?> _findScannedMatch(MusicTrack track) async {
    final path = track.localPath;
    if (path == null || path.isEmpty) return null;
    return _library.getMatchingLocalTrack(path);
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) return;
    if (_playing) {
      await _platform.pause();
    } else {
      await _platform.resume();
    }
  }

  /// Toggles playback, starting the remembered queue when the native player
  /// was already stopped (e.g. app restart). Returns false when nothing can
  /// be started so the caller can fall back to opening the detail page.
  Future<bool> togglePlayPauseOrStart({List<MusicTrack>? queue}) async {
    final track = _currentTrack;
    if (track == null) return false;
    if (_hasPlaybackSession) {
      await togglePlayPause();
      return true;
    }
    final effectiveQueue = queue != null && queue.isNotEmpty
        ? queue
        : _effectiveQueue;
    final containsTrack = effectiveQueue.any(
      (item) => item.trackKey == track.trackKey,
    );
    await playTrack(
      track,
      queue: containsTrack ? effectiveQueue : <MusicTrack>[track],
    );
    return true;
  }

  Future<void> seek(Duration position) => _platform.seek(position);

  Future<void> stop() async {
    await _persistCurrentPosition();
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

  Future<void> _persistCurrentPosition() async {
    final track = _currentTrack;
    if (track == null || !_hasPlaybackSession) return;
    if (track.sourceType == MusicSourceType.online && !track.isRemote) return;
    try {
      final updated = await _library.updatePlaybackPosition(track, _position);
      _replaceQueuedTrack(updated);
      _replaceSearchTrack(updated);
      _replaceDownloadedQueueTrack(updated);
      if (_currentTrack?.trackKey == updated.trackKey) {
        _currentTrack = updated;
      }
    } on Object catch (error) {
      debugPrint('[Music] persist position failed: $error');
    }
  }

  void _schedulePositionSave() {
    if (_positionSaveQueued) return;
    _positionSaveQueued = true;
    scheduleMicrotask(() async {
      _positionSaveQueued = false;
      await _persistCurrentPosition();
    });
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
    final queue = _effectiveQueue;
    if (queue.isEmpty) return;
    var index = _effectiveIndex;
    if (_playbackMode == MusicPlaybackMode.shuffle && queue.length > 1) {
      _queueIndex = _randomIndex(queue, index);
    } else {
      _queueIndex = (index - 1 + queue.length) % queue.length;
    }
    _queue = queue;
    await playTrack(_queue[_queueIndex]);
  }

  Future<void> next() async {
    final queue = _effectiveQueue;
    if (queue.isEmpty) return;
    final index = _effectiveIndex;
    if (_playbackMode == MusicPlaybackMode.singleLoop && index >= 0) {
      _queue = queue;
      _queueIndex = index;
      await playTrack(_queue[_queueIndex]);
      return;
    }
    if (_playbackMode == MusicPlaybackMode.shuffle && queue.length > 1) {
      _queueIndex = _randomIndex(queue, index);
    } else {
      _queueIndex = (index + 1) % queue.length;
    }
    _queue = queue;
    await playTrack(_queue[_queueIndex]);
  }

  int _randomIndex(List<MusicTrack> queue, int currentIndex) {
    var index = _random.nextInt(queue.length);
    while (index == currentIndex && queue.length > 1) {
      index = _random.nextInt(queue.length);
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

  /// Saves the current position without touching the queue or native player.
  Future<void> saveCurrentPosition() => _persistCurrentPosition();

  @visibleForTesting
  void simulatePlaybackStateForTesting({
    String trackKey = '',
    bool playing = false,
    bool buffering = false,
    bool completed = false,
    int positionMs = 0,
    int durationMs = 0,
  }) {
    _handlePlaybackState(<Object?, Object?>{
      'trackKey': trackKey,
      'playing': playing,
      'buffering': buffering,
      'completed': completed,
      'positionMs': positionMs,
      'durationMs': durationMs,
    });
  }

  @visibleForTesting
  void setNotificationOpenedCallbackForTesting(
    MusicNotificationOpened callback,
  ) {
    _onNotificationOpened = callback;
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
    _removeQueueTrack(track.trackKey);
    _downloadedQueue = List<MusicTrack>.unmodifiable(
      _downloadedQueue.where(
        (item) =>
            item.trackKey != track.trackKey &&
            (track.localPath == null || item.localPath != track.localPath),
      ),
    );
    notifyListeners();
  }

  void replaceCurrentTrack(MusicTrack track) => _replaceCurrent(track);

  void _replaceCurrent(MusicTrack track) {
    if (_currentTrack?.trackKey == track.trackKey) _setCurrentTrack(track);
    _replaceQueuedTrack(track);
    _replaceSearchTrack(track);
    _replaceDownloadedQueueTrack(track);
    notifyListeners();
  }

  void _removeQueueTrack(String trackKey) {
    final index = _queue.indexWhere((item) => item.trackKey == trackKey);
    if (index < 0) return;
    final updated = _queue.toList(growable: false)..removeAt(index);
    _queue = List<MusicTrack>.unmodifiable(updated);
    if (_queue.isEmpty) {
      _queueIndex = -1;
    } else if (index < _queueIndex) {
      _queueIndex--;
    } else if (_queueIndex >= _queue.length) {
      _queueIndex = 0;
    }
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
      _persistCurrentPosition();
      _setCurrentTrack(null);
      _queue = const <MusicTrack>[];
      _queueIndex = -1;
      _hasPlaybackSession = false;
    }
    if ((state['trackKey']?.toString() ?? '').isNotEmpty) {
      _hasPlaybackSession = true;
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
      if (_playing && _position > Duration.zero) _schedulePositionSave();
      _completionAdvanceInProgress = false;
    } else if (_queue.isNotEmpty && !_completionAdvanceInProgress) {
      _completionAdvanceInProgress = true;
      unawaited(_advanceAfterCompletion());
    }
  }

  Future<void> _handlePlaybackCommand(String command) async {
    if (_playbackCommandInProgress || _effectiveQueue.isEmpty) return;
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
    _resumeRequest.dispose();
    super.dispose();
  }
}
