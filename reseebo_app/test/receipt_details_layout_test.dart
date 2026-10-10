import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reseebo_app/core/adapters/mock_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/widgets/app_card.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';
import 'package:reseebo_app/features/comparison/widgets/supplier_comparison_table.dart';
import 'package:reseebo_app/features/receipts/screens/receipt_detail_screen.dart';
import 'package:reseebo_app/features/receipts/widgets/receipt_images_preview.dart';
import 'package:reseebo_app/features/receipts/widgets/saved_digital_receipt.dart';
import 'package:reseebo_app/core/models/models.dart';

void main() {
  testWidgets(
    'saved digital receipt keeps item evidence and individual compare actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = MockReseeboDataAdapter();
      final product = (await adapter.getProducts()).first;
      final comparison = await adapter.getProductComparison(product.id);
      final line = comparison.history.first.purchase;
      final detail = ReceiptDetail(
        receipt: Receipt(
          id: line.receiptId,
          supplier: line.supplier,
          purchasedAt: line.purchasedAt,
          hasPurchaseTime: line.hasPurchaseTime,
          createdAt: line.recordedAt,
          imagePath: line.imagePath,
          lineCount: 1,
          totalCents: line.netAmountCents,
          notes: 'Keep this purchase',
        ),
        lines: [line],
      );
      PurchaseRecord? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
                child: SavedDigitalReceipt(
                  detail: detail,
                  products: {product.id: product},
                  onCompare: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved purchase'), findsOneWidget);
      expect(find.text('Purchased items'), findsNothing);
      expect(find.text(line.purchaseLabel), findsOneWidget);
      expect(find.text('Source: Photo ${line.sourcePage + 1}'), findsOneWidget);
      await tester.ensureVisible(find.text('Compare'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare'));
      expect(selected, same(line));
      expect(find.text('Notes: Keep this purchase'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supplier receipt links open receipt details without an injected callback',
    (tester) async {
      final adapter = MockReseeboDataAdapter();
      final product = (await adapter.getProducts()).first;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductComparisonScreen(
            dataAdapter: adapter,
            productId: product.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent Supplier Prices'), findsOneWidget);
      final card = find
          .descendant(
            of: find.byType(SupplierComparisonTable),
            matching: find.byType(AppCard),
          )
          .first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Receipt details'), findsOneWidget);
      expect(find.text('RECORDED TOTAL'), findsOneWidget);
    },
  );

  testWidgets('compact receipts fit narrow screens and original photos open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = MockReseeboDataAdapter();
    final receipt = (await adapter.getRecentReceipts()).first;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ReceiptDetailScreen(adapter: adapter, receiptId: receipt.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RECORDED TOTAL'), findsOneWidget);
    expect(find.text('Purchased items'), findsNothing);
    expect(find.text('Saved purchase'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ReceiptImagesPreview)).height,
      lessThan(180),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Photo 1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo 1'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Original receipt · Photo 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
