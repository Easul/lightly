class MusicLyricLine {
  const MusicLyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

List<MusicLyricLine> parseLrc(String? source) {
  if (source == null || source.trim().isEmpty) {
    return const <MusicLyricLine>[];
  }
  final timestampPattern = RegExp(r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]');
  final lines = <MusicLyricLine>[];
  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) continue;
    final text = rawLine.replaceAll(timestampPattern, '').trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3) ?? '0';
      final milliseconds = fraction.length == 1
          ? int.parse(fraction) * 100
          : fraction.length == 2
          ? int.parse(fraction) * 10
          : int.parse(fraction.substring(0, 3));
      lines.add(
        MusicLyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

int activeLyricIndex(List<MusicLyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length - 1;
  var result = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (lines[middle].time <= position) {
      result = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return result;
}
