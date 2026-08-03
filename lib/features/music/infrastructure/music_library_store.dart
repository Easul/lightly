import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database_provider.dart';
import '../domain/music_track.dart';

class MusicLibraryStore {
  MusicLibraryStore({AppDatabaseProvider? database}) : _database = database;

  static final MusicLibraryStore instance = MusicLibraryStore();
  static const String table = 'music_tracks';

  AppDatabaseProvider? _database;

  set databaseProvider(AppDatabaseProvider provider) => _database = provider;

  Future<Database> get _db async {
    final provider = _database;
    if (provider == null) {
      throw StateError('MusicLibraryStore used before database injection');
    }
    return provider.database;
  }

  Future<List<MusicTrack>> list({
    MusicSourceType? sourceType,
    bool favoritesOnly = false,
    String? groupName,
  }) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (sourceType != null) {
      clauses.add('sourceType = ?');
      arguments.add(sourceType.name);
    }
    if (favoritesOnly) clauses.add('isFavorite = 1');
    if (groupName != null) {
      clauses.add('groupName = ?');
      arguments.add(groupName);
    }
    final db = await _db;
    final rows = await db.query(
      table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'COALESCE(lastPlayedAt, updatedAt) DESC, title COLLATE NOCASE',
    );
    return rows.map(MusicTrack.fromDatabaseMap).toList(growable: false);
  }

  Future<MusicTrack?> get(String trackKey) async {
    final db = await _db;
    final rows = await db.query(
      table,
      where: 'trackKey = ?',
      whereArgs: <Object?>[trackKey],
      limit: 1,
    );
    return rows.isEmpty ? null : MusicTrack.fromDatabaseMap(rows.single);
  }

  Future<MusicTrack> save(MusicTrack track) async {
    final updated = track.copyWith(updatedAt: DateTime.now());
    final db = await _db;
    await db.insert(
      table,
      updated.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return updated;
  }

  Future<void> replaceLocalTracks(List<MusicTrack> scanned) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final existingRows = await transaction.query(
        table,
        where: 'sourceType = ?',
        whereArgs: <Object?>[MusicSourceType.local.name],
      );
      final existing = <String, MusicTrack>{
        for (final row in existingRows)
          row['trackKey'] as String: MusicTrack.fromDatabaseMap(row),
      };
      final scannedKeys = scanned.map((track) => track.trackKey).toList();
      if (scannedKeys.isEmpty) {
        await transaction.delete(
          table,
          where: 'sourceType = ?',
          whereArgs: <Object?>[MusicSourceType.local.name],
        );
      } else {
        final placeholders = List.filled(scannedKeys.length, '?').join(',');
        await transaction.delete(
          table,
          where: 'sourceType = ? AND trackKey NOT IN ($placeholders)',
          whereArgs: <Object?>[MusicSourceType.local.name, ...scannedKeys],
        );
      }
      for (final track in scanned) {
        final previous = existing[track.trackKey];
        final merged = track.copyWith(
          isFavorite: previous?.isFavorite ?? false,
          groupName: previous?.groupName ?? '',
          lyric: previous?.lyric,
          translatedLyric: previous?.translatedLyric,
          updatedAt: previous?.updatedAt ?? DateTime.now(),
          lastPlayedAt: previous?.lastPlayedAt,
        );
        await transaction.insert(
          table,
          merged.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<MusicTrack> setFavorite(MusicTrack track, bool value) {
    return save(track.copyWith(isFavorite: value));
  }

  Future<MusicTrack> setGroup(MusicTrack track, String groupName) {
    return save(track.copyWith(groupName: groupName.trim()));
  }

  Future<void> delete(String trackKey) async {
    final db = await _db;
    await db.delete(
      table,
      where: 'trackKey = ?',
      whereArgs: <Object?>[trackKey],
    );
  }

  Future<List<String>> listGroups() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT DISTINCT groupName FROM $table WHERE groupName <> '' ORDER BY groupName COLLATE NOCASE",
    );
    return rows
        .map((row) => row['groupName'] as String)
        .toList(growable: false);
  }
}
