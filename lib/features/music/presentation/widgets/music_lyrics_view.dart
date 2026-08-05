import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/music_lyric.dart';

class MusicLyricsView extends StatelessWidget {
  const MusicLyricsView({
    super.key,
    required this.loading,
    required this.lyrics,
    required this.activeIndex,
    required this.scrollController,
    required this.onSeek,
  });

  final bool loading;
  final List<MusicLyricLine> lyrics;
  final int activeIndex;
  final ScrollController scrollController;
  final Future<void> Function(Duration position) onSeek;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (lyrics.isEmpty) return const Center(child: Text('暂无歌词'));
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
      itemExtent: 52,
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final active = index == activeIndex;
        return InkWell(
          onTap: () => unawaited(onSeek(lyrics[index].time)),
          child: Center(
            child: Text(
              lyrics[index].text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: active ? Theme.of(context).colorScheme.primary : null,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
