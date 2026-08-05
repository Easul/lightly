import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/music_player_controller.dart';
import '../../domain/music_track.dart';
import 'music_track_artwork.dart';

class MusicMiniPlayer extends StatefulWidget {
  const MusicMiniPlayer({super.key, required this.player, required this.onTap});

  final MusicPlayerController player;
  final Future<void> Function(MusicTrack track) onTap;

  @override
  State<MusicMiniPlayer> createState() => _MusicMiniPlayerState();
}

class _MusicMiniPlayerState extends State<MusicMiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_syncRotation);
    _syncRotation();
  }

  @override
  void didUpdateWidget(covariant MusicMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_syncRotation);
      widget.player.addListener(_syncRotation);
      _syncRotation();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_syncRotation);
    _rotation.dispose();
    super.dispose();
  }

  void _syncRotation() {
    if (widget.player.isPlaying) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.player,
      builder: (context, _) {
        final player = widget.player;
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            top: false,
            child: ListTile(
              onTap: () => unawaited(widget.onTap(track)),
              leading: RotationTransition(
                turns: _rotation,
                child: MusicTrackArtwork(
                  track: track,
                  size: 42,
                  circular: true,
                ),
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
                    tooltip: player.playbackModeLabel,
                    onPressed: player.cyclePlaybackMode,
                    icon: Icon(_playbackModeIcon(player.playbackMode)),
                  ),
                  IconButton(
                    tooltip: player.isPlaying ? '暂停' : '播放',
                    onPressed: () => unawaited(
                      player.togglePlayPauseOrStart(queue: player.queue),
                    ),
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

IconData _playbackModeIcon(MusicPlaybackMode mode) => switch (mode) {
  MusicPlaybackMode.listLoop => Icons.repeat_rounded,
  MusicPlaybackMode.singleLoop => Icons.repeat_one_rounded,
  MusicPlaybackMode.shuffle => Icons.shuffle_rounded,
};

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
