import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/music_track.dart';

class MusicTrackArtwork extends StatelessWidget {
  const MusicTrackArtwork({
    super.key,
    required this.track,
    this.size = 48,
    this.circular = false,
  });

  final MusicTrack track;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final borderRadius = circular
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(6);
    final artwork = track.artworkUrl;
    Widget child;
    if (artwork != null && artwork.startsWith('http')) {
      child = Image.network(
        artwork,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    } else if (artwork != null && artwork.startsWith('file://')) {
      child = Image.file(
        File.fromUri(Uri.parse(artwork)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    } else {
      child = _fallback(context);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.square(dimension: size, child: child),
    );
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.46,
        color: colorScheme.primary,
      ),
    );
  }
}
