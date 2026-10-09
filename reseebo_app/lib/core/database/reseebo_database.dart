import 'package:sqflite/sqflite.dart';

import 'migrations/migration_001_initial.dart';
import 'migrations/migration_002_receipt_pages.dart';
import 'migrations/migration_003_starter_catalog.dart';

class ReseeboDatabase {
  static const version = 3;
  static const migrations = <int, List<String>>{
    1: initialSchema,
    2: receiptPagesSchema,
    3: starterCatalogSchema,
  };

  /// The caller owns the returned connection. Supplying a factory/path allows
  /// real SQLite tests without replacing production persistence with a mock.
  static Future<Database> open({
    required DatabaseFactory factory,
    required String path,
  }) => factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, newVersion) => _migrate(db, 0, newVersion),
      onUpgrade: _migrate,
      onDowngrade: (db, oldVersion, newVersion) =>
          throw StateError('A newer Reseebo database cannot be downgraded.'),
    ),
  );

  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var next = oldVersion + 1; next <= newVersion; next++) {
      for (final sql in migrations[next]!) {
        await db.execute(sql);
      }
    }
  }
}
