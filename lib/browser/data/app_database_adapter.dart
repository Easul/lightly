import 'package:sqflite/sqflite.dart';

import '../../core/storage/app_database_provider.dart';
import 'app_database.dart';

/// Adapts [AppDatabase] to the [AppDatabaseProvider] port.
///
/// Preserves the exact handle AI history previously used
/// (`AppDatabase.instance.database`). Lives on the storage side so the port
/// itself stays free of any concrete database dependency.
class AppDatabaseAdapter implements AppDatabaseProvider {
  AppDatabaseAdapter({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  @override
  Future<Database> get database => _database.database;
}
