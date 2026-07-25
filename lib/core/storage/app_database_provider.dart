import 'package:sqflite/sqflite.dart';

/// Cross-feature port for obtaining the app's shared SQLite database.
///
/// This exists so features that only need "the app database handle" (e.g. AI
/// chat history) do not import a concrete, browser-named database class and do
/// not create a `feature → feature` dependency. The storage owner provides an
/// adapter implementing this port; the composition root injects it.
///
/// Contract: [database] opens (once) and returns the shared database. It does
/// not own the schema of any individual feature — callers reference their own
/// table names. The physical file and schema are unchanged by this port.
abstract class AppDatabaseProvider {
  Future<Database> get database;
}
