import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reseebo_app/core/services/ocr_service.dart';
import 'package:reseebo_app/core/services/receipt_parser.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

/// Opt-in local diagnostics: photos are supplied by adb, never app downloads.
/// Output can contain receipt data; retain it locally outside source control.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const folder = String.fromEnvironment('RECEIPT_SAMPLE_DIR');
  const names = ['dali', 'waltermart', 'puregold', 'savemore', 'sm_hypermart', 'pos_demo'];
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
        final prepared = await images.prepareRecognition(path, enhance: true);
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
      }
    } finally {
      await ocr.close();
      await images.deleteGenerated(generated, originalPath: '');
    }
  });
}
