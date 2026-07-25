import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/ai_tools/ai_history_database.dart';
import 'package:lightly/browser/data/app_database.dart';
import 'package:lightly/browser/data/app_database_adapter.dart';
import 'package:lightly/browser/models/browser_download_record.dart';
import 'package:lightly/browser/services/browser_download_store.dart';
import 'package:lightly/browser/services/browser_favorite_service.dart';
import 'package:lightly/browser/services/browser_history_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late String databasePath;
  AppDatabase? appDatabase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databasePath = p.join(
      await getDatabasesPath(),
      'app_database_test_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() async {
    await appDatabase?.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  test('upgrades schema v3 to v4 without replacing existing data', () async {
    final legacyDatabase = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE ${AppDatabase.historyTable} (
              id INTEGER PRIMARY KEY,
              url TEXT NOT NULL,
              title TEXT NOT NULL,
              visitedAt INTEGER NOT NULL,
              visitCount INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await database.execute('''
            CREATE TABLE ${AppDatabase.historyVisitsTable} (
              id INTEGER PRIMARY KEY,
              url TEXT NOT NULL,
              title TEXT NOT NULL,
              visitedAt INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ${AppDatabase.downloadTable} (
              id INTEGER PRIMARY KEY,
              url TEXT NOT NULL,
              fileName TEXT NOT NULL,
              status TEXT NOT NULL,
              savedPath TEXT,
              totalBytes INTEGER NOT NULL DEFAULT 0,
              bytesReceived INTEGER NOT NULL DEFAULT 0,
              createdAt INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE ${AppDatabase.favoriteTable} (
              id INTEGER PRIMARY KEY,
              url TEXT NOT NULL,
              title TEXT NOT NULL,
              createdAt INTEGER NOT NULL,
              sortOrder INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.insert(AppDatabase.historyTable, <String, Object?>{
            'url': 'https://legacy.example',
            'title': 'Legacy',
            'visitedAt': 1,
            'visitCount': 2,
          });
          await database.insert(AppDatabase.favoriteTable, <String, Object?>{
            'url': 'https://favorite.example',
            'title': 'Favorite',
            'createdAt': 1,
            'sortOrder': 0,
          });
        },
      ),
    );
    await legacyDatabase.close();

    appDatabase = AppDatabase.forTesting(databasePath);
    final upgraded = await appDatabase!.database;

    expect(await upgraded.getVersion(), AppDatabase.schemaVersion);
    expect(await _rowCount(upgraded, AppDatabase.historyTable), 1);
    expect(await _rowCount(upgraded, AppDatabase.favoriteTable), 1);
    expect(await _rowCount(upgraded, AiHistoryDatabase.sessionTable), 0);
    expect(await _rowCount(upgraded, AiHistoryDatabase.messageTable), 0);
  });

  test('repositories clear only the data category they own', () async {
    appDatabase = AppDatabase.forTesting(databasePath);
    final database = await appDatabase!.database;
    final history = BrowserHistoryService(database: appDatabase);
    final favorites = BrowserFavoriteService(database: appDatabase);
    final downloads = BrowserDownloadStore(database: appDatabase);
    final aiHistory = AiHistoryDatabase(
      database: AppDatabaseAdapter(database: appDatabase),
    );

    await history.insert(url: 'https://history.example', title: 'History');
    await favorites.insert(url: 'https://favorite.example', title: 'Favorite');
    await downloads.insert(
      BrowserDownloadRecord(
        url: 'https://download.example/file',
        fileName: 'file.bin',
        status: 'completed',
        savedPath: '/tmp/file.bin',
        totalBytes: 4,
        bytesReceived: 4,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
    final session = await aiHistory.createSession('Session');
    await aiHistory.addMessage(
      sessionId: session.id,
      role: 'user',
      content: 'private',
    );

    await history.clearHistory();
    expect(await _rowCount(database, AppDatabase.historyTable), 0);
    expect(await _rowCount(database, AppDatabase.historyVisitsTable), 0);
    expect(await _rowCount(database, AppDatabase.favoriteTable), 1);
    expect(await _rowCount(database, AppDatabase.downloadTable), 1);
    expect(await _rowCount(database, AiHistoryDatabase.sessionTable), 1);
    expect(await _rowCount(database, AiHistoryDatabase.messageTable), 1);

    await favorites.clearAll();
    expect(await _rowCount(database, AppDatabase.favoriteTable), 0);
    expect(await _rowCount(database, AppDatabase.downloadTable), 1);
    expect(await _rowCount(database, AiHistoryDatabase.sessionTable), 1);

    await downloads.clearAll();
    expect(await _rowCount(database, AppDatabase.downloadTable), 0);
    expect(await _rowCount(database, AiHistoryDatabase.sessionTable), 1);
    expect(await _rowCount(database, AiHistoryDatabase.messageTable), 1);
  });
}

Future<int> _rowCount(Database database, String table) async {
  final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return (rows.single['count'] as num).toInt();
}
