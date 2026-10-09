import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/state/capture_state.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'bundled native OCR retains word bounds and receipt after database reopen',
    (tester) async {
      // A generated, legible image tests the native pipeline, not real-store OCR
      // accuracy. A separate database keeps the owner's ledger untouched.
      final cache = await getTemporaryDirectory();
      final root = await Directory(
        '${cache.path}/ocr-smoke-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final image = img.Image(width: 1600, height: 730);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      const rows = [
        'SUPPLIER A',
        'OCTOBER 8, 2026',
        'TIME 02:30 PM',
        '2 PC COFFEE ORIGINAL 26G 168.00',
        'TOTAL 168.00',
      ];
      for (var index = 0; index < rows.length; index++) {
        img.drawString(
          image,
          rows[index],
          font: img.arial48,
          x: 60,
          y: 45 + index * 105,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
      final original = File('${root.path}/original.png');
      final originalBytes = img.encodePng(image);
      await original.writeAsBytes(originalBytes);
      Future<SqliteReseeboDataAdapter> open() => SqliteReseeboDataAdapter.open(
        databasePath: '${root.path}/smoke.sqlite',
        mediaDirectory: Directory('${root.path}/media'),
      );
      var adapter = await open();
      final starterCatalog = await adapter.getProducts();
      expect(starterCatalog.length, greaterThanOrEqualTo(150));
      expect(
        starterCatalog.every(
          (product) =>
              product.photoPath?.startsWith('asset:assets/catalog/images/') ==
              true,
        ),
        isTrue,
      );
      expect(await adapter.getRecentReceipts(), isEmpty);
      expect((await adapter.getStoreProfile()).name, 'Sari-sari Store');
      expect((await adapter.getStoreProfile()).defaultMarkupPercent, 20);
      final capture = CaptureState(
        adapter: adapter,
        initialImagePath: original.path,
      );
      ReceiptReviewState? review;
      try {
        await adapter.saveProduct(
          const Product(
            id: 'coffee',
            name: 'Coffee',
            brand: 'Brand X',
            variant: 'Original',
            size: '26g',
          ),
        );
        final draft = await capture.recognize();
        expect(draft, isNotNull, reason: capture.error);
        expect(draft!.purchasedAt, DateTime(2026, 10, 8, 14, 30));
        expect(draft.hasPurchaseTime, isTrue);
        expect(draft.lines, hasLength(1));
        expect(draft.lines.single.quantity, 2);
        expect(draft.lines.single.unit, PurchaseUnit.piece);
        expect(draft.lines.single.grossAmountCents, 16800);
        expect(
          draft.ocrPages.single.recognitionImagePath,
          isNot(original.path),
        );
        final tokens = draft.ocrPages.single.textLines
            .expand((line) => line.tokens)
            .toList();
        expect(
          tokens.where((token) => token.text.contains('168.00')),
          isNotEmpty,
        );
        expect(
          tokens.every((token) => token.width > 0 && token.height > 0),
          isTrue,
        );
        review = ReceiptReviewState(adapter: adapter, draft: draft);
        await review.load();
        review.draft.supplierName = 'Supplier A';
        review.draft.dateConfirmed = true;
        review.draft.lines.single.productId = 'coffee';
        review.confirmLine(review.draft.lines.single);
        expect(review.problem, isNull);
        final saved = await review.save();
        expect(saved.unitCostsCents, [8400.0]);
        await adapter.close();
        adapter = await open();
        expect((await adapter.getProducts()).length, starterCatalog.length + 1);
        final receipt = await adapter.getReceipt(saved.receiptId);
        expect(receipt.receipt.purchasedAt, DateTime(2026, 10, 8, 14, 30));
        expect(receipt.lines.single.costPerPieceCents, 8400);
        expect(receipt.receipt.imagePaths, hasLength(1));
        expect(
          await File(receipt.receipt.imagePath).readAsBytes(),
          originalBytes,
        );
        expect(await original.readAsBytes(), originalBytes);
      } finally {
        review?.dispose();
        capture.dispose();
        await adapter.close();
        await root.delete(recursive: true);
      }
    },
  );
}
