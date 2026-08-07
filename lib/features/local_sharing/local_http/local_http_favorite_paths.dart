import 'package:path/path.dart' as p;

List<String> normalizeLocalHttpFavoritePaths(Iterable<String> paths) {
  final normalized = <String>{};
  for (final rawPath in paths) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    normalized.add(p.posix.normalize(trimmed));
  }
  return normalized.toList(growable: false);
}
