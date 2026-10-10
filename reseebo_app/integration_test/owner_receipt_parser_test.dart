import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reseebo_app/core/adapters/sqlite_reseebo_data_adapter.dart';
import 'package:reseebo_app/core/models/models.dart';
import 'package:reseebo_app/features/receipt_scan/services/local_receipt_image_service.dart';

/// Opt-in exact-photo regression through bundled OCR and the production adapter.
/// Photos are supplied locally by adb; no receipt content is logged or saved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const folder = String.fromEnvironment('RECEIPT_SAMPLE_DIR');
  testWidgets(
    'owner receipt fields stay associated through native OCR',
    (tester) async {
      expect(folder, isNotEmpty);
      final cache = await getTemporaryDirectory();
      final root = await cache.createTemp('owner-parser-check-');
      final adapter = await SqliteReseeboDataAdapter.open(
        databasePath: '${root.path}/verification.sqlite',
        mediaDirectory: Directory('${root.path}/media'),
      );
      final images = LocalReceiptImageService();
      try {
        for (final name in ['user_wellbest', 'user_dali']) {
          final original = '$folder/$name.jpg';
          expect(await File(original).exists(), isTrue);
          final enhanced = await images.prepareRecognition(
            original,
            enhance: true,
          );
          try {
            for (final path in [original, enhanced]) {
              final draft = await adapter.processReceiptImage(
                original,
                recognitionImagePath: path,
                comparisonImagePath: original,
              );
              expect(draft.lines.every((line) => !line.confirmed), isTrue);
              if (name == 'user_wellbest') {
                expect(draft.lines, hasLength(2));
                expect(draft.detectedTotalCents, 25050);
                expect(draft.lines.map((line) => line.quantity), [10, 1]);
                expect(draft.lines.first.description, contains('BIRCH'));
                expect(draft.lines.last.description, contains('ARIEL'));
                expect(draft.lines.first.printedItemCode, '001747347');
                expect(draft.lines.first.grossAmountCents, isNull);
                expect(draft.lines.last.grossAmountCents, 9300);
                expect(draft.lines.every((line) => line.unit == null), isTrue);
              } else {
                expect(draft.lines, hasLength(3));
                expect(draft.detectedTotalCents, 23450);
                expect(draft.lines.map((line) => line.quantity), [null, 1, 3]);
                expect(draft.lines.map((line) => line.grossAmountCents), [
                  14400,
                  2750,
                  6300,
                ]);
                expect(
                  draft.lines.every((line) => line.unit == PurchaseUnit.piece),
                  isTrue,
                );
                expect(draft.lines.first.description, contains('Fiesta'));
                expect(draft.lines[1].description, contains('Zippy'));
                expect(draft.lines.last.description, contains('Carne'));
              }
            }
          } finally {
            if (enhanced != original) await File(enhanced).delete();
          }
        }
      } finally {
        await adapter.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
