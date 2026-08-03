import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/music_player_controller.dart';
import '../../domain/music_track.dart';
import 'music_track_artwork.dart';

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key, required this.player, required this.onTap});

  final MusicPlayerController player;
  final Future<void> Function(MusicTrack track) onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            top: false,
            child: ListTile(
              onTap: () => unawaited(onTap(track)),
              leading: MusicTrackArtwork(
                track: track,
                size: 42,
                circular: true,
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                player.playbackError ?? track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: player.playbackError == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: player.isPlaying ? '暂停' : '播放',
                    onPressed: () => unawaited(player.togglePlayPause()),
                    icon: Icon(
                      player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => unawaited(player.stop()),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class MusicSectionTitle extends StatelessWidget {
  const MusicSectionTitle({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
