import 'package:flutter/material.dart';

import '../../domain/music_track.dart';

class MusicTrackMetadata extends StatelessWidget {
  const MusicTrackMetadata({
    super.key,
    required this.track,
    this.playbackError,
  });

  final MusicTrack track;
  final String? playbackError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 3),
          Text(
            '${track.artist} · ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (track.groupName.isNotEmpty)
            Text(
              track.groupName,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          if (playbackError != null)
            Text(
              playbackError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
