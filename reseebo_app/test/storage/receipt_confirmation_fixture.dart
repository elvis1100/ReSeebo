import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:reseebo_app/core/adapters/i_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoOcr implements OcrService {
  @override
  Future<void> close() async {}
  @override
  Future<List<OcrTextLine>> recognize(String path) =>
      throw StateError('Storage must not perform OCR');
}

class ReceiptConfirmationFixture {
  late Directory root;
  late Directory media;
  late SqliteReseeboDataAdapter adapter;
  late Database db;
  DateTime now = DateTime.utc(2026, 10, 10);
  int _photo = 0;
  String get databasePath => p.join(root.path, 'records.sqlite');

  Future<void> setUp() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('reseebo-confirm-');
    media = Directory(p.join(root.path, 'owned'));
    await reopen();
  }

  Future<void> reopen() async {
    adapter = await SqliteReseeboDataAdapter.open(
      databaseFactory: databaseFactoryFfi,
      databasePath: databasePath,
      mediaDirectory: media,
      ocrService: _NoOcr(),
      starterProducts: const [],
      clock: () => now,
    );
    db = await databaseFactoryFfi.openDatabase(databasePath);
  }

  Future<void> tearDown() async {
    await adapter.close();
    await root.delete(recursive: true);
  }

  Future<String> photo() async {
    final pixels = image.Image(width: 3, height: 7)
      ..setPixelRgb(0, 0, ++_photo, 2, 3);
    final file = File(p.join(root.path, 'photo-$_photo.png'));
    await file.writeAsBytes(image.encodePng(pixels));
    return file.path;
  }

  Future<ReceiptDraft> draft({String? productId, int amount = 100000}) async =>
      ReceiptDraft(
        operationId: 'draft-$_photo',
        imagePath: await photo(),
        supplierName: 'Supplier A',
        purchasedAt: DateTime(2026, 10, 9),
        dateConfirmed: true,
        rawText: 'COFFEE ORIGINAL OCR',
        lines: [
          ParsedLineItem(
            id: 'temporary-line',
            description: 'Coffee Brand Original 26g',
            productId: productId,
            quantity: 10,
            unit: PurchaseUnit.piece,
            piecesPerPack: 1,
            grossAmountCents: amount,
            extractedAmountCents: 100000,
            confirmed: true,
          ),
        ],
      );

  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT count(*) AS n FROM $table')).single['n']
          as int;
}
