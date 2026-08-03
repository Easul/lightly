import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/app_toast.dart';
import '../application/music_player_controller.dart';
import '../domain/music_track.dart';
import 'music_track_page.dart';
import 'widgets/music_library_widgets.dart';
import 'widgets/music_track_artwork.dart';

class MusicDownloadsPage extends StatefulWidget {
  const MusicDownloadsPage({super.key});

  @override
  State<MusicDownloadsPage> createState() => _MusicDownloadsPageState();
}

class _MusicDownloadsPageState extends State<MusicDownloadsPage> {
  final MusicPlayerController _player = MusicPlayerController.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_player.initialize());
  }

  Future<void> _open(MusicTrack track, List<MusicTrack> queue) async {
    if (track.sourceUri.startsWith('file://')) {
      final path = track.localPath ?? Uri.parse(track.sourceUri).toFilePath();
      if (path.isNotEmpty && !await File(path).exists()) {
        if (!mounted) return;
        unawaited(AppToast.show('文件不存在或已被移动'));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicTrackPage(
          track: track,
          queue: queue,
          leavePlayerQueueOnExit: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音乐下载记录')),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _player,
          _player.activeTrackKeyChanges,
        ]),
        builder: (context, _) {
          final tracks = _player.downloadedQueue;
          if (tracks.isEmpty) {
            return const MusicEmptyState(
              icon: Icons.download_done_rounded,
              label: '暂无已下载歌曲',
            );
          }
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              12 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isCurrent =
                  _player.currentTrack?.trackKey == track.trackKey;
              return ListTile(
                selected: isCurrent,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                onTap: () => unawaited(_open(track, tracks)),
                leading: MusicTrackArtwork(track: track),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.localPath ?? track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isCurrent
                    ? Icon(
                        Icons.graphic_eq_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : const Icon(Icons.chevron_right_rounded),
              );
            },
          );
        },
      ),
    );
  }
}
