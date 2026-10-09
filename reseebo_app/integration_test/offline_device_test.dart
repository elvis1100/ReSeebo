import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/main.dart';

/// Uses a fresh temporary database without touching the owner's records.
/// Disable internet beforehand to verify offline native recognition.
/// The printed fixture checks native OCR availability, not real-receipt accuracy.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled multi-photo OCR, empty launch, and native SQLite reopen', (
    tester,
  ) async {
    final documents = await getApplicationDocumentsDirectory();
    final root = await documents.createTemp('reseebo-device-check-');
    final databasePath = p.join(root.path, 'check.sqlite');
    final media = Directory(p.join(root.path, 'images'));
    var adapter = await SqliteReseeboDataAdapter.open(
      databasePath: databasePath,
      mediaDirectory: media,
    );
    try {
      debugPrint('DEVICE_CHECK: temporary database ready');
      expect(await adapter.getProducts(), isEmpty);
      expect(await adapter.getRecentReceipts(), isEmpty);
      await tester.pumpWidget(ReseeboApp(adapter: adapter));
      await tester.pumpAndSettle();
      expect(find.text('Reseebo'), findsWidgets);
      debugPrint('DEVICE_CHECK: empty launch rendered');

      final photo = img.Image(width: 1100, height: 800);
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      var y = 70;
      for (final line in [
        'SUPPLIER ONE',
        '09/10/2026',
        'BRANDX COFFEE 26G',
        '2 PACKS   168.00',
        'TOTAL 168.00',
      ]) {
        img.drawString(
          photo,
          line,
          font: img.arial48,
          x: 65,
          y: y,
          color: img.ColorRgb8(0, 0, 0),
        );
        y += 125;
      }
      final source = File(p.join(root.path, 'printed-check.png'));
      await source.writeAsBytes(img.encodePng(photo), flush: true);

      await adapter.updateStoreProfile(
        StoreProfile(
          name: 'Device test store',
          ownerName: 'Owner',
          defaultMarkupPercent: 20,
          photoPath: source.path,
        ),
      );
      const productId = 'device-coffee';
      await adapter.saveProduct(
        Product(
          id: productId,
          name: 'Brand X Coffee',
          brand: 'Brand X',
          variant: 'Original',
          size: '26g',
          photoPath: source.path,
          markupPercent: 0,
          sellingPriceCents: 1000,
        ),
      );
      final secondPhoto = img.Image(width: 1100, height: 800);
      img.fill(secondPhoto, color: img.ColorRgb8(255, 255, 255));
      var nextY = 70;
      for (final line in [
        'SUPPLIER ONE',
        'PAGE 2',
        'BRANDX COFFEE 26G',
        '2 PACKS   168.00',
        'TOTAL 168.00',
      ]) {
        img.drawString(
          secondPhoto,
          line,
          font: img.arial48,
          x: 65,
          y: nextY,
          color: img.ColorRgb8(0, 0, 0),
        );
        nextY += 125;
      }
      final secondSource = File(p.join(root.path, 'printed-page-2.png'));
      await secondSource.writeAsBytes(img.encodePng(secondPhoto), flush: true);
      debugPrint('DEVICE_CHECK: starting native page recognition');
      final draft = await adapter.processReceiptImages([
        source.path,
        secondSource.path,
      ]);
      debugPrint('DEVICE_CHECK: native recognition returned');
      expect(draft.lines, hasLength(2));
      expect(draft.lines.first.description.toUpperCase(), contains('BRANDX'));
      expect(draft.lines.first.quantity, 2);
      expect(draft.lines.first.unit, PurchaseUnit.pack);
      expect(draft.lines.first.grossAmountCents, 16800);
      expect(draft.lines.last.possibleDuplicateOf, draft.lines.first.id);
      // This fixture intentionally repeats one row in overlapping photos.
      // Resolve it explicitly, then supply the facts that OCR cannot establish.
      draft.lines.removeLast();
      expect(draft.rawText.toUpperCase(), contains('BRANDX'));
      expect(draft.textLines, isNotEmpty);
      draft.supplierName = 'Supplier One';
      draft.purchasedAt = DateTime(2026, 10, 9);
      draft.dateConfirmed = true;
      draft.receiptNumber = 'OFFLINE-CHECK';
      draft.totalDifferenceConfirmed = true;
      draft.lines
        ..clear()
        ..add(
          ParsedLineItem(
            description: 'BRANDX COFFEE 26G',
            productId: productId,
            quantity: 2,
            unit: PurchaseUnit.pack,
            piecesPerPack: 10,
            grossAmountCents: 16800,
            confirmed: true,
          ),
        );
      final result = await adapter.saveConfirmedReceipt(draft);
      debugPrint('DEVICE_CHECK: transaction committed');
      expect(result.unitCostsCents.single, 840);
      expect((await adapter.saveConfirmedReceipt(draft)).alreadySaved, isTrue);
      debugPrint('DEVICE_CHECK: retry verified');
      final detail = await adapter.getReceipt(result.receiptId);
      debugPrint('DEVICE_CHECK: saved pages loaded');
      expect(await File(detail.receipt.imagePath).exists(), isTrue);
      expect(detail.receipt.imagePath, isNot(source.path));
      expect(detail.receipt.imagePaths, hasLength(2));
      expect(await File(detail.receipt.imagePaths[1]).exists(), isTrue);
      await source.delete();
      await secondSource.delete();
      debugPrint('DEVICE_CHECK: external sources removed');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Checking saved records…')),
        ),
      );
      debugPrint('DEVICE_CHECK: dashboard disposed');
      await adapter.close();
      debugPrint('DEVICE_CHECK: database and recognizer closed');
      adapter = await SqliteReseeboDataAdapter.open(
        databasePath: databasePath,
        mediaDirectory: media,
      );
      final reopenedReceipt = await adapter.getReceipt(result.receiptId);
      debugPrint('DEVICE_CHECK: persistence reopened');
      expect(reopenedReceipt.receipt.imagePaths, detail.receipt.imagePaths);
      for (final path in reopenedReceipt.receipt.imagePaths) {
        expect(await File(path).exists(), isTrue);
      }
      final profile = await adapter.getStoreProfile();
      expect(profile.name, 'Device test store');
      expect(profile.defaultMarkupPercent, 20);
      expect(await File(profile.photoPath!).exists(), isTrue);
      final comparison = await adapter.getProductComparison(productId);
      expect(comparison.effectiveMarkupPercent, 0);
      expect(comparison.latestPrices.single.purchase.costPerPieceCents, 840);
      expect(await File(comparison.product.photoPath!).exists(), isTrue);
      expect(
        (await adapter.matchAliases('BRANDX COFFEE 26G')).single.exactAlias,
        isTrue,
      );
      final restock = await adapter.calculateRestock(
        productId: productId,
        targetPieces: 21,
        additionalCost: 30,
      );
      expect(restock.suppliers.single.purchasedPieces, 30);
      expect(restock.suppliers.single.subtotalCents, 25200);
      expect(restock.suppliers.single.totalCents, 28200);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await adapter.close();
      await root.delete(recursive: true);
      debugPrint('DEVICE_CHECK: temporary records removed');
    }
  });
}
