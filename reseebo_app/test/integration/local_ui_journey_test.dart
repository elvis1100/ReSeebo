import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/features/comparison/screens/product_comparison_screen.dart';
import 'package:reseebo_app/features/dashboard/screens/dashboard_screen.dart';
import 'package:reseebo_app/core/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _UnusedOcr implements OcrService {
  @override
  Future<List<OcrTextLine>> recognize(String imagePath) async =>
      throw StateError('This host check does not invoke native OCR.');
  @override
  Future<void> close() async {}
}

Future<void> _settleLocal(WidgetTester tester) async {
  // SQLite FFI replies and image files use real I/O. Alternate real event-loop
  // turns with widget pumps rather than advancing only the test's fake clock.
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Local SQLite screen did not finish loading.');
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'saved SQLite purchases drive dashboard and comparison at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory directory;
      late SqliteReseeboDataAdapter adapter;
      await tester.runAsync(() async {
        await (FontLoader(
          'Inter',
        )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        directory = await Directory.systemTemp.createTemp('reseebo-live-ui-');
        var recorded = DateTime(2026, 10, 9, 9);
        adapter = await SqliteReseeboDataAdapter.open(
          databaseFactory: databaseFactoryFfi,
          databasePath: p.join(directory.path, 'real.sqlite'),
          mediaDirectory: Directory(p.join(directory.path, 'media')),
          ocrService: _UnusedOcr(),
          clock: () {
            recorded = recorded.add(const Duration(seconds: 1));
            return recorded;
          },
        );
        await adapter.updateStoreProfile(
          const StoreProfile(
            name: 'Aling Nena Store',
            defaultMarkupPercent: 20,
          ),
        );
        await adapter.saveProduct(
          const Product(
            id: 'coffee',
            name: 'Brand X Original Coffee',
            brand: 'Brand X',
            variant: 'Original',
            size: '26g',
            sellingPriceCents: 1000,
          ),
        );
        await adapter.saveProduct(
          const Product(
            id: 'large-coffee',
            name: 'Brand X Original Coffee',
            brand: 'Brand X',
            variant: 'Original',
            size: '33g',
          ),
        );
        var serial = 0;
        for (final values in [
          ('Puregold', 'Poblacion', DateTime(2026, 10, 1), 16000),
          ('Wholesaler', 'Market', DateTime(2026, 10, 5), 15600),
          ('Puregold', 'Poblacion', DateTime(2026, 10, 8), 16800),
          ('Puregold', 'Poblacion', DateTime(2026, 10, 8), 17200),
        ]) {
          final image = img.Image(width: 280, height: 380);
          img.fill(image, color: img.ColorRgb8(255, 255, 255));
          img.drawString(
            image,
            '${values.$1}\nCoffee 26g\n${values.$4 / 100}\nReceipt ${++serial}',
            font: img.arial24,
            x: 12,
            y: 40,
            color: img.ColorRgb8(0, 0, 0),
          );
          final source = File(p.join(directory.path, 'receipt-$serial.png'));
          await source.writeAsBytes(img.encodePng(image));
          await adapter.saveConfirmedReceipt(
            ReceiptDraft(
              imagePath: source.path,
              supplierName: values.$1,
              supplierBranch: values.$2,
              purchasedAt: values.$3,
              dateConfirmed: true,
              receiptNumber: 'REF-$serial',
              lines: [
                ParsedLineItem(
                  description: 'BRANDX COF ORIG 26G',
                  productId: 'coffee',
                  quantity: 2,
                  unit: PurchaseUnit.pack,
                  piecesPerPack: 10,
                  grossAmountCents: values.$4,
                  confirmed: true,
                ),
              ],
            ),
          );
        }
      });
      try {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: boundary,
              child: DashboardScreen(adapter: adapter),
            ),
          ),
        );
        await _settleLocal(tester);
        expect(find.text('Aling Nena Store'), findsOneWidget);
        expect(find.text('Puregold · Poblacion'), findsWidgets);
        expect(find.text('₱172.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['RESEEBO_SCREENSHOT_DIR']
            case final String output) {
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File(
              p.join(output, 'dashboard.png'),
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: boundary,
              child: ProductComparisonScreen(
                adapter: adapter,
                productId: 'coffee',
              ),
            ),
          ),
        );
        await _settleLocal(tester);
        expect(find.text('Latest recorded supplier prices'), findsOneWidget);
        expect(find.text('₱7.80'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['RESEEBO_SCREENSHOT_DIR']
            case final String output) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File(
              p.join(output, 'comparison.png'),
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.scrollUntilVisible(
          find.text('₱8.60'),
          260,
          scrollable: find.descendant(
            of: find.byKey(const PageStorageKey('comparison-prices')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('₱8.60'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final comparison = await tester.runAsync(
          () => adapter.getProductComparison('coffee'),
        );
        expect(comparison!.history.length, 4);
        expect(
          comparison.history.where((row) => row.orderingNote != null).length,
          2,
        );
        expect(
          (await tester.runAsync(
            () => adapter.getProductComparison('large-coffee'),
          ))!.history,
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await adapter.close();
          await directory.delete(recursive: true);
        });
      }
    },
  );
}
