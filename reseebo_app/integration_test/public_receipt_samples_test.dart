import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/features/receipt_scan/state/receipt_review_state.dart';
import 'receipt_ocr_offline_test.dart' as smoke;
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

/// Opt-in local diagnostics: photos are supplied by adb, never app downloads.
/// Output can contain receipt data; retain it locally outside source control.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const folder = String.fromEnvironment('RECEIPT_SAMPLE_DIR');
  const restart = bool.fromEnvironment('RECEIPT_VERIFY_RESTART');
  if (restart) {
    testWidgets(
      'saved public receipt persists across process restart offline',
      (tester) async {
        final support = await getApplicationSupportDirectory();
        final root = Directory('${support.path}/receipt-autofill-verification');
        final marker =
            jsonDecode(await File('${root.path}/saved.json').readAsString())
                as Map<String, dynamic>;
        final adapter = await SqliteReseeboDataAdapter.open(
          databasePath: '${root.path}/samples.sqlite',
          mediaDirectory: Directory('${root.path}/media'),
        );
        try {
          final detail = await adapter.getReceipt(
            marker['receiptId'] as String,
          );
          expect(detail.lines, hasLength(6));
          expect(detail.receipt.totalCents, 19760);
          expect(detail.receipt.purchasedAt, DateTime(2026, 4, 17, 18, 47));
          expect(detail.lines.map((line) => line.netAmountCents), [
            1590,
            3795,
            1025,
            6300,
            4100,
            2950,
          ]);
          expect(
            await File(detail.receipt.imagePath).readAsBytes(),
            await File('$folder/savemore.jpg').readAsBytes(),
          );
          expect(
            (await adapter.getSuppliers()).single.dateOrder,
            NumericDateOrder.monthFirst,
          );
          expect(
            await adapter.getProductCategories(),
            contains('Verification groceries'),
          );
          final categoryProduct = (await adapter.getProductById(
            'verification-product',
          ))!;
          expect(categoryProduct.size, '33g');
          expect(categoryProduct.nameOnly, isTrue);
          await adapter.removeProductCategory('Verification groceries');
          expect(
            (await adapter.getProductById(categoryProduct.id))!.category,
            isEmpty,
          );
          expect(
            (await adapter.getReceipt(marker['receiptId'] as String)).lines,
            hasLength(6),
          );
        } finally {
          await adapter.close();
          await root.delete(recursive: true);
        }
      },
    );
    return;
  }
  smoke.main();
  const names = [
    'dali',
    'waltermart',
    'puregold',
    'savemore',
    'sm_hypermart',
    'pos_demo',
  ];
  testWidgets('public grocery receipt OCR diagnostics', (tester) async {
    expect(
      folder,
      isNotEmpty,
      reason: 'Supply RECEIPT_SAMPLE_DIR with adb photos',
    );
    final ocr = MlKitOcrService();
    final images = LocalReceiptImageService();
    final generated = <String?>[];
    try {
      for (final name in names) {
        final path = '$folder/$name.jpg';
        expect(await File(path).exists(), isTrue);
        var recognitionSource = path;
        if (name == 'pos_demo') {
          // The vendor image includes explanatory text beside the receipt.
          // Use the same local crop transform available in the capture editor.
          recognitionSource = await images.transform(
            path,
            crop: [.14, 0, .52, 1],
          );
          generated.add(recognitionSource);
        }
        final prepared = await images.prepareRecognition(
          recognitionSource,
          enhance: true,
        );
        generated.add(prepared);
        final lines = await ocr.recognize(prepared);
        final draft = ReceiptParser().parse(imagePath: path, textLines: lines);
        // One record per sample makes host-side evidence extraction repeatable.
        // ignore: avoid_print
        print(
          'RECEIPT_SAMPLE ${jsonEncode({
            'id': name,
            'lines': [
              for (final line in lines) {
                  'text': line.text,
                  'left': line.left,
                  'top': line.top,
                  'width': line.width,
                  'height': line.height,
                  'tokens': [
                    for (final token in line.tokens) {'text': token.text, 'left': token.left, 'top': token.top, 'width': token.width, 'height': token.height},
                  ],
                },
            ],
            'date': draft.purchasedAt?.toIso8601String(),
            'total': draft.detectedTotalCents,
            'items': [
              for (final line in draft.lines) {'description': line.description, 'quantity': line.quantity, 'unit': line.unit?.name, 'amount': line.grossAmountCents},
            ],
          })}',
        );
        if (name == 'pos_demo') {
          expect(draft.detectedTotalCents, 16145);
          expect(draft.lines, isNotEmpty);
        }
        if (name == 'savemore') {
          expect(draft.lines, hasLength(6));
          expect(draft.lines.map((line) => line.quantity), [2, 1, 1, 3, 2, 1]);
          expect(draft.detectedTotalCents, 19760);
          expect(draft.purchasedAt, DateTime(2026, 4, 17, 18, 47));
          final support = await getApplicationSupportDirectory();
          final root = await Directory(
            '${support.path}/receipt-autofill-verification',
          ).create(recursive: true);
          final adapter = await SqliteReseeboDataAdapter.open(
            databasePath: '${root.path}/samples.sqlite',
            mediaDirectory: Directory('${root.path}/media'),
          );
          final review = ReceiptReviewState(adapter: adapter, draft: draft);
          try {
            await adapter.saveSupplier(
              const Supplier(
                id: 'sample-store',
                name: 'Verification sample',
                dateOrder: NumericDateOrder.monthFirst,
              ),
            );
            await review.load();
            review.draft.supplierId = 'sample-store';
            review.draft.supplierName = 'Verification sample';
            review.draft.supplierBranch = '';
            review.draft.dateConfirmed = true;
            const amounts = [1590, 3795, 1025, 6300, 4100, 2950];
            // Corrections transcribed from inspected pixels simulate owner
            // review; they are never counted as automatic extraction success.
            for (var index = 0; index < amounts.length; index++) {
              final line = review.draft.lines[index];
              review.editText(
                line,
                ReceiptLineField.amount,
                (amounts[index] / 100).toStringAsFixed(2),
              );
              review.confirmLine(line);
            }
            expect(review.problem, isNull);
            final saved = await review.save();
            await adapter.addProductCategory('Verification groceries');
            await adapter.saveProduct(
              const Product(
                id: 'verification-product',
                name: 'Bear Brand Fortified Milk',
                brand: '',
                variant: '',
                size: '33g',
                nameOnly: true,
                category: 'Verification groceries',
              ),
            );
            await File(
              '${root.path}/saved.json',
            ).writeAsString(jsonEncode({'receiptId': saved.receiptId}));
          } finally {
            review.dispose();
            await adapter.close();
          }
        }
      }
    } finally {
      await ocr.close();
      await images.deleteGenerated(generated, originalPath: '');
    }
  });
}
