import 'package:sqflite/sqflite.dart';

import '../../core/storage/app_database_provider.dart';
import 'browser_database.dart';

/// Adapts [BrowserDatabase] to the [AppDatabaseProvider] port.
///
/// Preserves the exact handle AI history previously used
/// (`BrowserDatabase.instance.database`). Lives on the storage side so the port
/// itself stays free of any concrete database dependency. Renaming the concrete
/// class to `AppDatabase` (Phase 4) does not affect the port or its consumers.
class BrowserDatabaseAppProvider implements AppDatabaseProvider {
  BrowserDatabaseAppProvider({BrowserDatabase? database})
    : _database = database ?? BrowserDatabase.instance;

  final BrowserDatabase _database;

  @override
  Future<Database> get database => _database.database;
}
