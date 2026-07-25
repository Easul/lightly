import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/ai_tools/ai_history_database.dart';
import 'package:lightly/browser/data/app_database.dart';
import 'package:lightly/browser/data/app_database_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final database = AiHistoryDatabase.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = '${await getDatabasesPath()}/browser_data.db';
    await databaseFactory.deleteDatabase(path);
    // AI history now depends on the AppDatabaseProvider port; inject the
    // shared-database adapter the way the composition root does at runtime.
    database.databaseProvider = AppDatabaseAdapter();
  });

  tearDownAll(AppDatabase.instance.close);

  test('chat sessions and messages support CRUD', () async {
    final session = await database.createSession('First chat');
    final message = await database.addMessage(
      sessionId: session.id,
      role: 'user',
      content: 'hello',
    );

    expect((await database.listSessions()).single.title, 'First chat');
    expect((await database.listMessages(session.id)).single.content, 'hello');

    await database.renameSession(session.id, 'Renamed chat');
    await database.updateMessage(message.id, 'updated');

    expect((await database.listSessions()).single.title, 'Renamed chat');
    expect((await database.listMessages(session.id)).single.content, 'updated');

    await database.deleteMessage(message.id);
    expect(await database.listMessages(session.id), isEmpty);

    await database.deleteSession(session.id);
    expect(await database.listSessions(), isEmpty);

    final db = await AppDatabase.instance.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames, contains(AppDatabase.historyTable));
    expect(tableNames, contains(AppDatabase.favoriteTable));
    expect(tableNames, contains(AiHistoryDatabase.sessionTable));
    expect(tableNames, contains(AiHistoryDatabase.messageTable));
  });

  test('throws when used before a database provider is injected', () async {
    // A fresh instance with no injected provider must fail loudly rather than
    // silently fall back to a browser database — the composition root is
    // responsible for wiring it during bootstrap.
    final unwired = AiHistoryDatabase();
    await expectLater(unwired.listSessions(), throwsStateError);
  });
}
