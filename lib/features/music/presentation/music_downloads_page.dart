import 'dart:async';

import 'package:flutter/material.dart';

import '../application/music_player_controller.dart';
import '../domain/music_track.dart';
import '../infrastructure/music_library_store.dart';
import 'music_track_page.dart';
import 'widgets/music_library_widgets.dart';
import 'widgets/music_track_artwork.dart';

class MusicDownloadsPage extends StatefulWidget {
  const MusicDownloadsPage({super.key});

  @override
  State<MusicDownloadsPage> createState() => _MusicDownloadsPageState();
}

class _MusicDownloadsPageState extends State<MusicDownloadsPage> {
  final MusicLibraryStore _library = MusicLibraryStore.instance;
  final MusicPlayerController _player = MusicPlayerController.instance;
  List<MusicTrack>? _tracks;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final tracks = await _library.list(sourceType: MusicSourceType.downloaded);
    if (mounted) setState(() => _tracks = tracks);
  }

  Future<void> _open(MusicTrack track) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicTrackPage(track: track, queue: _tracks),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    return Scaffold(
      appBar: AppBar(title: const Text('音乐下载记录')),
      body: tracks == null
          ? const Center(child: CircularProgressIndicator())
          : tracks.isEmpty
          ? const MusicEmptyState(
              icon: Icons.download_done_rounded,
              label: '暂无已下载歌曲',
            )
          : AnimatedBuilder(
              animation: _player.activeTrackKeyChanges,
              builder: (context, _) => ListView.builder(
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
                    onTap: () => unawaited(_open(track)),
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
              ),
            ),
    );
  }
}
