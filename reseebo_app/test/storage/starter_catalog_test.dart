import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/database/reseebo_database.dart';
import 'package:reseebo_app/core/models/product.dart';
import 'package:reseebo_app/core/services/starter_catalog_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_adapter_test.dart' show FakeOcr;

const starter = Product(
  id: 'off_test',
  name: 'Example Coffee',
  brand: 'Example',
  variant: 'Coffee',
  size: '26 g',
  barcode: '1234567890123',
  photoPath: 'asset:assets/catalog/images/example.webp',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reseebo-catalog-');
    db = await ReseeboDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, 'catalog.sqlite'),
    );
  });
  tearDown(() async {
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> seed(List<Product> products) =>
      StarterCatalogService.seed(db, products, now: DateTime.utc(2026, 10, 9));

  test(
    'bundled catalog has distinct identities, small photos and no prices',
    () async {
      final products = await StarterCatalogService.load();
      expect(products.length, greaterThanOrEqualTo(200));
      expect(
        products.map((product) => product.id).toSet().length,
        products.length,
      );
      for (final product in products) {
        expect(product.brand.trim(), isNotEmpty);
        expect(product.variant.trim(), isNotEmpty);
        expect(product.size.trim(), isNotEmpty);
        expect(product.sellingPriceCents, isNull);
        expect(product.markupPercent, isNull);
        final photo = await rootBundle.load(product.photoPath!.substring(6));
        expect(photo.lengthInBytes, inInclusiveRange(1, 20000));
      }
    },
  );

  test(
    'first seed creates product suggestions and leaves all purchase data empty',
    () async {
      await seed([starter]);
      final rows = await db.query('products');
      expect(rows.single['photo_path'], starter.photoPath);
      expect(rows.single['selling_price_cents'], isNull);
      expect(rows.single['markup_percent'], isNull);
      for (final table in [
        'purchase_lines',
        'receipts',
        'suppliers',
        'product_aliases',
      ]) {
        expect(await db.query(table), isEmpty);
      }
    },
  );

  test(
    'reopen preserves owner edits and does not recreate deleted seed items',
    () async {
      final removed = starter.copyWith(
        id: 'off_removed',
        barcode: '9876543210987',
        size: '50 g',
      );
      await seed([starter, removed]);
      await db.update(
        'products',
        {
          'name': 'My coffee',
          'selling_price_cents': 1200,
          'photo_path': '/owner/photo.jpg',
        },
        where: 'id = ?',
        whereArgs: [starter.id],
      );
      await db.delete('products', where: 'id = ?', whereArgs: [removed.id]);
      final path = db.path;
      await db.close();
      db = await ReseeboDatabase.open(factory: databaseFactoryFfi, path: path);
      await seed([starter, removed]);
      final rows = await db.query('products');
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'My coffee');
      expect(rows.single['selling_price_cents'], 1200);
      expect(rows.single['photo_path'], '/owner/photo.jpg');
      expect(await db.query('catalog_seed_entries'), hasLength(2));
    },
  );

  test(
    'barcode and exact identity matches preserve existing owner products',
    () async {
      await seed([starter.copyWith(id: 'owner_product', name: 'My item')]);
      // Remove the synthetic test seed marker to model an existing owner product.
      await db.delete('catalog_seed_entries');
      await seed([starter]);
      expect(await db.query('products'), hasLength(1));
      expect((await db.query('products')).single['id'], 'owner_product');
      expect((await db.query('products')).single['name'], 'My item');
      final sameIdentity = starter.copyWith(
        id: 'off_other_barcode',
        barcode: '3333333333333',
        size: '26g',
      );
      await seed([sameIdentity]);
      expect(await db.query('products'), hasLength(1));
    },
  );

  test(
    'a failed seed rolls back both product inserts and ledger entries',
    () async {
      await expectLater(
        seed([
          starter,
          starter.copyWith(
            id: 'invalid',
            name: '',
            barcode: '2222222222222',
            size: '50g',
          ),
        ]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('products'), isEmpty);
      expect(await db.query('catalog_seed_entries'), isEmpty);
    },
  );

  test(
    'adapter preserves asset photos when customizing a seeded product',
    () async {
      await db.close();
      final path = p.join(directory.path, 'adapter.sqlite');
      final adapter = await SqliteReseeboDataAdapter.open(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
        mediaDirectory: Directory(p.join(directory.path, 'media')),
        ocrService: FakeOcr(),
        starterProducts: [starter],
      );
      try {
        await adapter.saveProduct(starter.copyWith(sellingPriceCents: 950));
        final product = await adapter.getProductById(starter.id);
        expect(product!.photoPath, starter.photoPath);
        expect(product.sellingPriceCents, 950);
      } finally {
        await adapter.close();
      }
    },
  );
}
