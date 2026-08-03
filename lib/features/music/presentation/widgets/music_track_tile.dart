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
    return ListTile(
      onTap: onTap,
      leading: MusicTrackArtwork(track: track),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
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
