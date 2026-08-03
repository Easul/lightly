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
  const MusicTrackPage({super.key, required this.track, this.queue});

  final MusicTrack track;
  final List<MusicTrack>? queue;

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
  List<MusicLyricLine> _lyrics = const <MusicLyricLine>[];
  bool _loadingLyrics = false;
  bool _downloading = false;
  int _activeLyric = -1;

  bool get _isCurrent => _player.currentTrack?.trackKey == _track.trackKey;
  Duration get _position => _isCurrent ? _player.position : Duration.zero;
  Duration get _duration =>
      _isCurrent ? _player.duration : Duration(milliseconds: _track.durationMs);

  @override
  void initState() {
    super.initState();
    _player.addListener(_handlePlayerChanged);
    _syncRotation();
    unawaited(_loadStoredTrackAndLyrics());
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanged);
    _rotation.dispose();
    _lyricScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredTrackAndLyrics() async {
    final stored = await _library.get(_track.trackKey);
    if (stored != null) _track = stored;
    if (_track.isRemote && !(_track.lyric?.isNotEmpty ?? false)) {
      if (mounted) setState(() => _loadingLyrics = true);
      try {
        _track = await _player.ensureLyrics(_track);
      } catch (error) {
        _toast('$error');
      } finally {
        if (mounted) setState(() => _loadingLyrics = false);
      }
    }
    _lyrics = parseLrc(_track.lyric);
    if (mounted) setState(() {});
  }

  void _handlePlayerChanged() {
    final current = _player.currentTrack;
    if (current?.trackKey == _track.trackKey) _track = current!;
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
        await _player.playTrack(_track, queue: widget.queue);
      }
    } catch (error) {
      _toast('$error');
    }
  }

  Future<void> _seekToLyric(Duration position) async {
    try {
      if (!_isCurrent) {
        await _player.playTrack(_track, queue: widget.queue);
      }
      await _player.seek(position);
    } catch (error) {
      _toast('$error');
    }
  }

  Future<void> _toggleFavorite() async {
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

  Future<void> _download() async {
    if (_downloading || _track.sourceType == MusicSourceType.downloaded) return;
    setState(() => _downloading = true);
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
      );
      _track = await _library.save(playable);
      _player.replaceCurrentTrack(_track);
      if (mounted) setState(() {});
      _toast('歌曲已保存到 ${_track.localPath}');
    } catch (error) {
      _toast('下载失败：$error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  @override
  Widget build(BuildContext context) {
    final durationMs = _duration.inMilliseconds.clamp(1, 1 << 31).toDouble();
    final positionMs = _position.inMilliseconds
        .clamp(0, durationMs.toInt())
        .toDouble();
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
          IconButton(
            tooltip: _track.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => unawaited(_toggleFavorite()),
            icon: Icon(
              _track.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'group') unawaited(_setGroup());
              if (value == 'download') unawaited(_download());
            },
            itemBuilder: (_) => [
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
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
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
                    onChanged: _isCurrent
                        ? (value) => unawaited(
                            _player.seek(Duration(milliseconds: value.round())),
                          )
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一首',
                        onPressed: _player.hasPrevious
                            ? () => unawaited(_player.previous())
                            : null,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip: _isCurrent && _player.isPlaying ? '暂停' : '播放',
                        onPressed: () => unawaited(_playOrPause()),
                        iconSize: 30,
                        icon: Icon(
                          _isCurrent && _player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: '下一首',
                        onPressed: _player.hasNext
                            ? () => unawaited(_player.next())
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
