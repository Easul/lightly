import 'package:flutter/material.dart';

import '../../domain/music_track.dart';
import 'music_track_artwork.dart';

class MusicTrackTile extends StatelessWidget {
  const MusicTrackTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.onFavorite,
  });

  final MusicTrack track;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      track.artist,
      if (track.album.isNotEmpty && track.album != '未知专辑') track.album,
    ].join(' · ');
    final source = switch (track.sourceType) {
      MusicSourceType.local => ('本机', Icons.phone_android_rounded),
      MusicSourceType.downloaded => ('已下载', Icons.download_done_rounded),
      MusicSourceType.online => ('在线', Icons.cloud_outlined),
    };
    final sourceColor = switch (track.sourceType) {
      MusicSourceType.local => Theme.of(context).colorScheme.primary,
      MusicSourceType.downloaded => Theme.of(context).colorScheme.tertiary,
      MusicSourceType.online => Theme.of(context).colorScheme.secondary,
    };
    return ListTile(
      onTap: onTap,
      leading: MusicTrackArtwork(track: track),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Icon(source.$2, size: 14, color: sourceColor),
          const SizedBox(width: 3),
          Text(source.$1, style: TextStyle(color: sourceColor)),
          if (details.isNotEmpty) ...[
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        tooltip: track.isFavorite ? '取消收藏' : '收藏',
        onPressed: onFavorite,
        icon: Icon(
          track.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: track.isFavorite
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
    );
  }
}
