import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/app_toast.dart';
import '../../../services/shared_downloads_directory_service.dart';
import '../../../widgets/shared_download_access_dialog.dart';
import '../application/music_player_controller.dart';
import '../domain/music_lyric.dart';
import '../domain/music_track.dart';
import '../infrastructure/music_download_service.dart';
import '../infrastructure/music_library_store.dart';
import 'music_player_dialogs.dart';
import 'widgets/music_lyrics_view.dart';
import 'widgets/music_source_path.dart';
import 'widgets/music_track_artwork.dart';
import 'widgets/music_track_metadata.dart';

class MusicTrackPage extends StatefulWidget {
  const MusicTrackPage({
    super.key,
    required this.track,
    this.queue,
    this.resumeFromSaved = false,
    this.leavePlayerQueueOnExit = false,
  });

  final MusicTrack track;
  final List<MusicTrack>? queue;
  final bool resumeFromSaved;
  final bool leavePlayerQueueOnExit;

  @override
  State<MusicTrackPage> createState() => _MusicTrackPageState();
}

class _MusicTrackPageState extends State<MusicTrackPage>
    with SingleTickerProviderStateMixin {
  final MusicPlayerController _player = MusicPlayerController.instance;
  final MusicLibraryStore _library = MusicLibraryStore.instance;
  final SharedDownloadsDirectoryService _downloadsAccess =
      SharedDownloadsDirectoryService();
  final ScrollController _lyricScrollController = ScrollController();
  late final MusicDownloadService _downloadService = MusicDownloadService(
    downloadsAccess: _downloadsAccess,
  );
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  late MusicTrack _track = widget.track;
  late List<MusicTrack> _queue = widget.queue ?? const <MusicTrack>[];
  List<MusicLyricLine> _lyrics = const <MusicLyricLine>[];
  bool _loadingLyrics = false;
  bool _downloading = false;
  double? _downloadProgress;
  double? _seekPreviewMs;
  int _activeLyric = -1;
  int _trackLoadRequestId = 0;

  bool get _isCurrent => _player.currentTrack?.trackKey == _track.trackKey;
  Duration get _position {
    if (_isCurrent) return _player.position;
    if (widget.resumeFromSaved && _track.lastPositionMs > 0) {
      return Duration(milliseconds: _track.lastPositionMs);
    }
    return Duration.zero;
  }

  Duration get _duration =>
      _isCurrent ? _player.duration : Duration(milliseconds: _track.durationMs);

  @override
  void initState() {
    super.initState();
    _player.addListener(_handlePlayerChanged);
    _syncRotation();
    unawaited(_loadStoredTrackAndLyrics());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.resumeFromSaved || _isCurrent) return;
      // 用户已确认断点续播：自动从上次位置继续播放。
      unawaited(_playOrPause());
    });
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanged);
    if (widget.leavePlayerQueueOnExit) {
      _player.detachQueue();
    }
    _rotation.dispose();
    _lyricScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredTrackAndLyrics() async {
    final requestId = ++_trackLoadRequestId;
    var loadedTrack = await _library.get(_track.trackKey) ?? _track;
    if (requestId != _trackLoadRequestId) return;
    if (loadedTrack.isRemote && !(loadedTrack.lyric?.isNotEmpty ?? false)) {
      if (mounted) setState(() => _loadingLyrics = true);
      try {
        loadedTrack = await _player.ensureLyrics(loadedTrack);
      } catch (error) {
        _toast('$error');
      } finally {
        if (mounted && requestId == _trackLoadRequestId) {
          setState(() => _loadingLyrics = false);
        }
      }
    }
    if (!mounted || requestId != _trackLoadRequestId) return;
    _track = loadedTrack;
    _lyrics = parseLrc(loadedTrack.lyric);
    setState(() {});
  }

  void _handlePlayerChanged() {
    final current = _player.currentTrack;
    if (current?.trackKey == _track.trackKey) {
      _track = current!;
    } else if (current != null &&
        _queue.any((track) => track.trackKey == current.trackKey)) {
      _track = current;
      _lyrics = parseLrc(current.lyric);
      _activeLyric = -1;
      _seekPreviewMs = null;
      unawaited(_loadStoredTrackAndLyrics());
    }
    if (_player.queue.isNotEmpty) {
      _queue = _player.queue;
    }
    _syncRotation();
    final index = activeLyricIndex(_lyrics, _position);
    if (index != _activeLyric) {
      _activeLyric = index;
      _scrollToActiveLyric(index);
    }
    if (mounted) setState(() {});
  }

  void _syncRotation() {
    if (_isCurrent && _player.isPlaying) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  void _scrollToActiveLyric(int index) {
    if (index < 0 || !_lyricScrollController.hasClients) return;
    final viewport = _lyricScrollController.position.viewportDimension;
    final target = (index * 52.0 - viewport / 2 + 26).clamp(
      0.0,
      _lyricScrollController.position.maxScrollExtent,
    );
    unawaited(
      _lyricScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _playOrPause() async {
    try {
      if (_isCurrent) {
        await _player.togglePlayPause();
      } else {
        final resumeAt = widget.resumeFromSaved && _track.lastPositionMs > 0
            ? Duration(milliseconds: _track.lastPositionMs)
            : null;
        await _player.playTrack(
          _track,
          queue: _queue,
          startAt: resumeAt,
          savePosition: resumeAt == null,
        );
      }
    } catch (error) {
      _toast('$error');
    }
  }

  Future<void> _seekToLyric(Duration position) async {
    try {
      if (!_isCurrent) {
        await _player.playTrack(_track, queue: _queue);
      }
      await _player.seek(position);
    } catch (error) {
      _toast('$error');
    }
  }

  Future<void> _commitSeek(double value) async {
    try {
      await _player.seek(Duration(milliseconds: value.round()));
    } catch (error) {
      _toast('$error');
    } finally {
      if (mounted) setState(() => _seekPreviewMs = null);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_track.isRemote) return;
    try {
      _track = await _player.setFavorite(_track, !_track.isFavorite);
      if (mounted) setState(() {});
    } catch (error) {
      _toast('收藏操作失败：$error');
    }
  }

  Future<void> _setGroup() async {
    final groups = await _library.listGroups();
    if (!mounted) return;
    final group = await showMusicGroupDialog(
      context,
      currentGroup: _track.groupName,
      existingGroups: groups,
    );
    if (group == null) return;
    _track = await _player.setGroup(_track, group);
    if (mounted) setState(() {});
  }

  Future<void> _deleteTrack() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地歌曲？'),
        content: Text('将同时删除“${_track.title}”的本地文件和音乐记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _player.deleteLocalTrack(_track);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _toast('删除失败：$error');
    }
  }

  Future<void> _download() async {
    if (_downloading || _track.sourceType == MusicSourceType.downloaded) return;
    setState(() {
      _downloading = true;
      _downloadProgress = null;
    });
    try {
      var playable = await _player.ensurePlayable(_track);
      var preferShared = true;
      var requestPermission = false;
      if (!await _downloadsAccess.hasFileAccessPermission()) {
        if (!mounted) return;
        final choice = await showSharedDownloadAccessDialog(
          context,
          actionLabel: '歌曲',
        );
        if (choice == SharedDownloadAccessChoice.cancel) return;
        preferShared = choice == SharedDownloadAccessChoice.requestPermission;
        requestPermission = preferShared;
      }
      playable = await _downloadService.download(
        playable,
        preferSharedDownloads: preferShared,
        requestSharedAccessIfNeeded: requestPermission,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = totalBytes == null || totalBytes <= 0
                ? null
                : (receivedBytes / totalBytes).clamp(0, 1).toDouble();
          });
        },
      );
      // ensurePlayable already fetched missing lyrics/artwork for the remote
      // id and saved them under the same track key. Merge that metadata back
      // onto the download result (which owns the fresh file path and toast
      // target) so saving it cannot clobber the cached lyric/artwork slots
      // with nulls and the page always renders the newest values.
      final cached = await _library.get(playable.trackKey);
      _track = await _library.save(
        playable.copyWith(
          lyric: cached?.lyric ?? playable.lyric,
          translatedLyric: cached?.translatedLyric ?? playable.translatedLyric,
          artworkUrl: cached?.artworkUrl ?? playable.artworkUrl,
        ),
      );
      await _player.registerDownloadedTrack(_track);
      _lyrics = parseLrc(_track.lyric);
      if (mounted) setState(() {});
      _toast('歌曲已保存到 ${_track.localPath ?? _track.sourceUri}');
    } catch (error) {
      _toast('下载失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  bool get _canSkip {
    if (_queue.isNotEmpty) return _queue.length > 1;
    return _player.queue.length > 1;
  }

  Future<void> _skip(bool forward) async {
    if (!_canSkip) return;
    // Before the queue ever started playing, jump inside this page's own
    // group instead of relying on controller state.
    if (!_isCurrent && _queue.length > 1) {
      final index = _queue.indexWhere(
        (track) => track.trackKey == _track.trackKey,
      );
      if (index < 0) return;
      final offset = forward ? 1 : -1;
      final target = _queue[(index + offset + _queue.length) % _queue.length];
      try {
        await _player.playTrack(target, queue: _queue);
      } catch (error) {
        _toast('$error');
      }
      return;
    }
    try {
      if (forward) {
        await _player.next();
      } else {
        await _player.previous();
      }
    } catch (error) {
      _toast('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = _duration.inMilliseconds.clamp(1, 1 << 31).toDouble();
    final positionMs = (_seekPreviewMs ?? _position.inMilliseconds.toDouble())
        .clamp(0, durationMs.toInt())
        .toDouble();
    final displayPosition = Duration(milliseconds: positionMs.round());
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
          if (!_track.isRemote)
            IconButton(
              tooltip: _track.isFavorite ? '取消收藏' : '收藏',
              onPressed: () => unawaited(_toggleFavorite()),
              icon: Icon(
                _track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
            ),
          AnimatedBuilder(
            animation: _player,
            builder: (context, _) => IconButton(
              tooltip: _player.playbackModeLabel,
              onPressed: _player.cyclePlaybackMode,
              icon: Icon(_playbackModeIcon(_player.playbackMode)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'group') unawaited(_setGroup());
              if (value == 'download') unawaited(_download());
              if (value == 'delete') unawaited(_deleteTrack());
            },
            itemBuilder: (_) => [
              if (!_track.isRemote)
                const PopupMenuItem(
                  value: 'group',
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined),
                    title: Text('歌曲分组'),
                  ),
                ),
              if (_track.isRemote &&
                  _track.sourceType != MusicSourceType.downloaded)
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download_rounded),
                    title: Text('下载歌曲'),
                  ),
                ),
              if (_track.sourceType != MusicSourceType.online)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('删除本地文件和记录'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _rotation,
                  child: MusicTrackArtwork(
                    track: _track,
                    size: 184,
                    circular: true,
                  ),
                ),
                IconButton.filled(
                  tooltip: _isCurrent && _player.isPlaying ? '暂停' : '播放',
                  onPressed: _downloading || _player.isBuffering
                      ? null
                      : () => unawaited(_playOrPause()),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(58),
                    backgroundColor: Colors.black.withValues(alpha: 0.38),
                    disabledBackgroundColor: Colors.black.withValues(
                      alpha: 0.38,
                    ),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                  ),
                  icon: _downloading || _player.isBuffering
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            value: _downloading ? _downloadProgress : null,
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isCurrent && _player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 36,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            MusicTrackMetadata(
              track: _track,
              playbackError: _isCurrent ? _player.playbackError : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Column(
                children: [
                  Slider(
                    value: positionMs,
                    max: durationMs,
                    onChangeStart: _isCurrent
                        ? (value) => setState(() => _seekPreviewMs = value)
                        : null,
                    onChanged: _isCurrent
                        ? (value) => setState(() => _seekPreviewMs = value)
                        : null,
                    onChangeEnd: _isCurrent
                        ? (value) => unawaited(_commitSeek(value))
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(displayPosition)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一首',
                        onPressed: _canSkip
                            ? () => unawaited(_skip(false))
                            : null,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip: _isCurrent && _player.isPlaying ? '暂停' : '播放',
                        onPressed: () => unawaited(_playOrPause()),
                        iconSize: 30,
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.30),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          disabledBackgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          disabledForegroundColor: Theme.of(
                            context,
                          ).colorScheme.outline,
                        ),
                        icon: Icon(
                          _isCurrent && _player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: _canSkip
                            ? () => unawaited(_skip(true))
                            : null,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: MusicLyricsView(
                loading: _loadingLyrics,
                lyrics: _lyrics,
                activeIndex: _activeLyric,
                scrollController: _lyricScrollController,
                onSeek: _seekToLyric,
              ),
            ),
            if (_track.sourceType != MusicSourceType.online)
              MusicSourcePath(track: _track),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

IconData _playbackModeIcon(MusicPlaybackMode mode) => switch (mode) {
  MusicPlaybackMode.listLoop => Icons.repeat_rounded,
  MusicPlaybackMode.singleLoop => Icons.repeat_one_rounded,
  MusicPlaybackMode.shuffle => Icons.shuffle_rounded,
};
