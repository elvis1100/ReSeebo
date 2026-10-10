import 'package:sqflite/sqflite.dart';

import 'migrations/migration_001_initial.dart';
import 'migrations/migration_002_receipt_pages.dart';
import 'migrations/migration_003_starter_catalog.dart';
import 'migrations/migration_004_name_only_products.dart';
import 'migrations/migration_005_supplier_date_order.dart';
import 'migrations/migration_006_product_categories.dart';
import 'migrations/migration_007_supplier_product_aliases.dart';
import 'migrations/migration_008_reviewable_receipts.dart';

class ReseeboDatabase {
  static const version = 8;
  static const migrations = <int, List<String>>{
    1: initialSchema,
    2: receiptPagesSchema,
    3: starterCatalogSchema,
    4: nameOnlyProductsSchema,
    5: supplierDateOrderSchema,
    6: productCategoriesSchema,
    7: supplierProductAliasesSchema,
    8: reviewableReceiptsSchema,
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
      // Table rebuilds run inside the upgrade transaction. Enforcement is restored
      // before callers receive the connection; migration checks all references.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = OFF'),
      onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError('Database migration contains invalid references.');
    }
  }
}
