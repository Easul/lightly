import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/ai_tools/ai_history_database.dart';
import 'package:lightly/browser/data/browser_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final database = AiHistoryDatabase.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = '${await getDatabasesPath()}/browser_data.db';
    await databaseFactory.deleteDatabase(path);
  });

  tearDownAll(BrowserDatabase.instance.close);

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

    final db = await BrowserDatabase.instance.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames, contains(BrowserDatabase.historyTable));
    expect(tableNames, contains(BrowserDatabase.favoriteTable));
    expect(tableNames, contains(BrowserDatabase.aiChatSessionTable));
    expect(tableNames, contains(BrowserDatabase.aiChatMessageTable));
  });
}
