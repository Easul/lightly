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

  /// Finds the scanned local row that represents the same physical file as
  /// [path]. The scan key may use the MediaStore content URI, the derived
  /// /storage path, or the basename, so matching falls back in that order.
  Future<MusicTrack?> getMatchingLocalTrack(String path) async {
    final direct = await get('local:$path');
    if (direct != null) return direct;
    final db = await _db;
    final rows = await db.query(
      table,
      where: 'sourceType = ? AND localPath = ?',
      whereArgs: <Object?>[MusicSourceType.local.name, path],
      limit: 1,
    );
    if (rows.isNotEmpty) return MusicTrack.fromDatabaseMap(rows.single);
    final segments = path.split('/');
    final fileName = segments.isEmpty ? '' : segments.last;
    if (fileName.isEmpty) return null;
    final suffixRows = await db.query(
      table,
      where: "sourceType = ? AND (localPath LIKE ? OR trackKey LIKE ?)",
      whereArgs: <Object?>[
        MusicSourceType.local.name,
        '%/$fileName',
        '%/$fileName',
      ],
      limit: 2,
    );
    if (suffixRows.length == 1) {
      return MusicTrack.fromDatabaseMap(suffixRows.single);
    }
    return null;
  }

  /// Every stored row carrying [remoteId], regardless of which track key
  /// prefix (online:/downplayed) it was saved under. Metadata cached on any
  /// of them belongs to the same song.
  Future<List<MusicTrack>> listByRemoteId(String remoteId) async {
    final db = await _db;
    final rows = await db.query(
      table,
      where: 'remoteId = ?',
      whereArgs: <Object?>[remoteId],
    );
    return rows.map(MusicTrack.fromDatabaseMap).toList(growable: false);
  }

  /// Patches lyric/artwork slots on every row carrying [remoteId] that is
  /// still missing them. Downloaded and online copies of one song live under
  /// different keys; filling them together keeps the local list, search
  /// results, and queue in sync with whatever was fetched once.
  Future<void> backfillRemoteMetadata(
    String remoteId, {
    String? lyric,
    String? translatedLyric,
    String? artworkUrl,
  }) async {
    final rows = await listByRemoteId(remoteId);
    for (final row in rows) {
      final patched = row.copyWith(
        lyric: row.lyric ?? lyric,
        translatedLyric: row.translatedLyric ?? translatedLyric,
        artworkUrl: row.artworkUrl ?? artworkUrl,
      );
      if (!identical(patched, row)) {
        await save(patched);
      }
    }
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
          lastPositionMs: previous?.lastPositionMs ?? 0,
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

  Future<MusicTrack> updatePlaybackPosition(
    MusicTrack track,
    Duration position,
  ) {
    final positionMs = position.inMilliseconds.clamp(0, 1 << 31);
    if (track.lastPositionMs == positionMs) {
      return Future<MusicTrack>.value(track);
    }
    return save(track.copyWith(lastPositionMs: positionMs));
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
