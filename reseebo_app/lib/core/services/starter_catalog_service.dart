import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

/// Bundled identities are suggestions, never evidence of purchases or prices.
/// A seed ledger prevents repeat inserts after owner edits or deletions.
class StarterCatalogService {
  static const assetPath = 'assets/catalog/products.json';

  static Future<List<Product>> load({AssetBundle? bundle}) async {
    final data =
        jsonDecode(await (bundle ?? rootBundle).loadString(assetPath))
            as Map<String, dynamic>;
    return (data['products'] as List<dynamic>)
        .map((entry) {
          final row = entry as Map<String, dynamic>;
          return Product(
            id: 'off_${row['barcode']}',
            name: row['name'] as String,
            brand: row['brand'] as String,
            variant: row['variant'] as String,
            size: row['size'] as String,
            category: row['category'] as String,
            barcode: row['barcode'] as String,
            photoPath: 'asset:${row['image_asset']}',
          );
        })
        .toList(growable: false);
  }

  /// Inserts the supplied catalog atomically. Existing barcode/identity matches
  /// are recorded as handled without changing any owner data. No image copies,
  /// supplier records, prices, aliases or purchase records are created.
  static Future<void> seed(
    Database db,
    List<Product> products, {
    required DateTime now,
  }) async {
    final appliedAt = now.toUtc().millisecondsSinceEpoch;
    await db.transaction((transaction) async {
      final applied = (await transaction.query(
        'catalog_seed_entries',
      )).map((row) => row['source_key'] as String).toSet();
      for (final product in products) {
        if (applied.contains(product.id)) continue;
        final existing = await transaction.rawQuery(
          '''SELECT id FROM products WHERE id = ?
             OR (barcode != '' AND barcode = ?)
             OR (lower(trim(brand)) = lower(trim(?))
                 AND lower(trim(variant)) = lower(trim(?))
                 AND lower(replace(size, ' ', '')) =
                     lower(replace(?, ' ', ''))) LIMIT 1''',
          [
            product.id,
            product.barcode,
            product.brand,
            product.variant,
            product.size,
          ],
        );
        if (existing.isEmpty) {
          if (product.category.trim().isNotEmpty) {
            await transaction.insert('product_categories', {
              'name': product.category.trim(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await transaction.insert('products', {
            'id': product.id,
            'name': product.name,
            'brand': product.brand,
            'variant': product.variant,
            'size': product.size,
            'category': product.category,
            'barcode': product.barcode,
            'photo_path': product.photoPath,
            'created_at': appliedAt,
            'updated_at': appliedAt,
          });
        }
        await transaction.insert('catalog_seed_entries', {
          'source_key': product.id,
          'applied_at': appliedAt,
        });
        applied.add(product.id);
      }
    });
  }
}
