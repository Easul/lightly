import 'package:flutter/material.dart';

import '../../domain/music_track.dart';

class MusicSourcePath extends StatelessWidget {
  const MusicSourcePath({super.key, required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              track.localPath ?? track.sourceUri,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
