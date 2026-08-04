import 'music_track.dart';

enum MusicSortField { addedTime, name, duration }

enum MusicSortOrder { descending, ascending }

class MusicLibrarySort {
  const MusicLibrarySort({
    this.field = MusicSortField.addedTime,
    this.order = MusicSortOrder.descending,
  });

  final MusicSortField field;
  final MusicSortOrder order;

  String get storageValue => '${field.name}.${order.name}';

  String get label => switch ((field, order)) {
    (MusicSortField.addedTime, MusicSortOrder.descending) => '按加入时间倒序',
    (MusicSortField.addedTime, MusicSortOrder.ascending) => '按加入时间正序',
    (MusicSortField.name, MusicSortOrder.descending) => '按名称倒序',
    (MusicSortField.name, MusicSortOrder.ascending) => '按名称正序',
    (MusicSortField.duration, MusicSortOrder.descending) => '按时长倒序',
    (MusicSortField.duration, MusicSortOrder.ascending) => '按时长正序',
  };

  static MusicLibrarySort parse(String? value) {
    const fallback = MusicLibrarySort();
    if (value == null) return fallback;
    final parts = value.split('.');
    if (parts.length != 2) return fallback;
    final field = MusicSortField.values.asNameMap()[parts[0]];
    final order = MusicSortOrder.values.asNameMap()[parts[1]];
    if (field == null || order == null) return fallback;
    return MusicLibrarySort(field: field, order: order);
  }

  static List<MusicLibrarySort> get options =>
      List<MusicLibrarySort>.unmodifiable(
        MusicSortField.values.expand(
          (field) => MusicSortOrder.values.map(
            (order) => MusicLibrarySort(field: field, order: order),
          ),
        ),
      );
}

/// Compares titles so embedded numbers sort by value ("1, 2, 10" instead of
/// "1, 10, 2"), then falls back to a case-insensitive text comparison.
int compareMusicTitles(String a, String b) {
  final aParts = _splitNumericRuns(a);
  final bParts = _splitNumericRuns(b);
  final length = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (var index = 0; index < length; index++) {
    final aPart = aParts[index];
    final bPart = bParts[index];
    final aNumber = aPart.$2;
    final bNumber = bPart.$2;
    if (aNumber != null && bNumber != null) {
      final byValue = aNumber.compareTo(bNumber);
      if (byValue != 0) return byValue;
      // Equal values: prefer the shorter digit run ("1" before "01").
      final byDigits = aPart.$1.length.compareTo(bPart.$1.length);
      if (byDigits != 0) return byDigits;
      continue;
    }
    final byText = aPart.$1.toLowerCase().compareTo(bPart.$1.toLowerCase());
    if (byText != 0) return byText;
  }
  final byLength = aParts.length.compareTo(bParts.length);
  if (byLength != 0) return byLength;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

List<(String, int?)> _splitNumericRuns(String value) {
  final parts = <(String, int?)>[];
  final buffer = StringBuffer();
  var inDigits = false;
  var started = false;
  void flush() {
    if (buffer.isEmpty) return;
    final text = buffer.toString();
    buffer.clear();
    parts.add(inDigits ? (text, int.parse(text)) : (text, null));
  }

  for (final codeUnit in value.codeUnits) {
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    if (started && isDigit != inDigits) flush();
    inDigits = isDigit;
    started = true;
    buffer.writeCharCode(codeUnit);
  }
  flush();
  return parts;
}

List<MusicTrack> sortMusicTracks(
  Iterable<MusicTrack> tracks,
  MusicLibrarySort sort,
) {
  final sorted = tracks.toList(growable: false);
  final direction = sort.order == MusicSortOrder.ascending ? 1 : -1;
  int tiebreak(MusicTrack a, MusicTrack b) {
    final byTitle = compareMusicTitles(a.title, b.title);
    if (byTitle != 0) return byTitle;
    return a.trackKey.compareTo(b.trackKey);
  }

  sorted.sort((a, b) {
    final primary = switch (sort.field) {
      MusicSortField.addedTime =>
        (a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      MusicSortField.name => compareMusicTitles(a.title, b.title),
      MusicSortField.duration => a.durationMs.compareTo(b.durationMs),
    };
    if (primary != 0) return primary * direction;
    return tiebreak(a, b);
  });
  return List<MusicTrack>.unmodifiable(sorted);
}
